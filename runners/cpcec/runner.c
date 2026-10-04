// CPCEC adapter implementing the cpc-validation runner protocol.
//
// CPCEC is compiled from its unmodified sources: this file #includes
// cpcec.c after renaming its main() and SDL_PollEvent(). CPCEC polls SDL
// exactly once per emulated frame, so the renamed poll is our per-frame hook:
// it drives the input script, counts frames, and finally writes the
// artefacts and exits. SDL itself runs with its dummy video/audio drivers.

#include <SDL2/SDL.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <sys/stat.h>
#include <unistd.h>

static int runner_poll(SDL_Event *event);
static void runner_delay(Uint32 ms) { (void)ms; }
static int runner_queue_audio(SDL_AudioDeviceID dev, const void *data, Uint32 len);

// Realtime mode stays on (so CPCEC never skips drawing a frame) but its
// pacing sleeps become no-ops.
#define SDL_PollEvent runner_poll
#define SDL_Delay runner_delay
#define SDL_QueueAudio runner_queue_audio
#define main cpcec_main
#include "cpcec.c"
#undef main
#undef SDL_QueueAudio
#undef SDL_Delay
#undef SDL_PollEvent

// -------------------------------------------------------------------------
// canonical screen output

// The canonical screen is CPCEC's default visible window: 48 CRTC characters
// (16 pixels each) by 268 scanlines, every scanline doubled.
#define CANON_W VIDEO_PIXELS_X
#define CANON_H VIDEO_PIXELS_Y

static const uint8_t canon_palette[32][3] = {
	{0x80, 0x80, 0x80}, {0x80, 0x80, 0x80}, {0x00, 0xff, 0x80}, {0xff, 0xff, 0x80},
	{0x00, 0x00, 0x80}, {0xff, 0x00, 0x80}, {0x00, 0x80, 0x80}, {0xff, 0x80, 0x80},
	{0xff, 0x00, 0x80}, {0xff, 0xff, 0x80}, {0xff, 0xff, 0x00}, {0xff, 0xff, 0xff},
	{0xff, 0x00, 0x00}, {0xff, 0x00, 0xff}, {0xff, 0x80, 0x00}, {0xff, 0x80, 0xff},
	{0x00, 0x00, 0x80}, {0x00, 0xff, 0x80}, {0x00, 0xff, 0x00}, {0x00, 0xff, 0xff},
	{0x00, 0x00, 0x00}, {0x00, 0x00, 0xff}, {0x00, 0x80, 0x00}, {0x00, 0x80, 0xff},
	{0x80, 0x00, 0x80}, {0x80, 0xff, 0x80}, {0x80, 0xff, 0x00}, {0x80, 0xff, 0xff},
	{0x80, 0x00, 0x00}, {0x80, 0x00, 0xff}, {0x80, 0x80, 0x00}, {0x80, 0x80, 0xff},
};

static uint32_t crc_table[256];

static void crc_init(void)
{
	for (uint32_t n = 0; n < 256; n++) {
		uint32_t c = n;
		for (int k = 0; k < 8; k++)
			c = (c & 1) ? 0xedb88320u ^ (c >> 1) : c >> 1;
		crc_table[n] = c;
	}
}

static uint32_t crc_update(uint32_t crc, const uint8_t *buf, size_t len)
{
	for (size_t i = 0; i < len; i++)
		crc = crc_table[(crc ^ buf[i]) & 0xff] ^ (crc >> 8);
	return crc;
}

static void put32(uint8_t *p, uint32_t v)
{
	p[0] = v >> 24, p[1] = v >> 16, p[2] = v >> 8, p[3] = v;
}

static void png_chunk(FILE *f, const char *type, const uint8_t *data, uint32_t len)
{
	uint8_t hdr[8];
	put32(hdr, len);
	memcpy(hdr + 4, type, 4);
	fwrite(hdr, 1, 8, f);
	if (len)
		fwrite(data, 1, len, f);
	uint32_t crc = crc_update(0xffffffffu, (const uint8_t *)type, 4);
	crc = crc_update(crc, data, len) ^ 0xffffffffu;
	uint8_t c[4];
	put32(c, crc);
	fwrite(c, 1, 4, f);
}

// Writes an RGB PNG using stored (uncompressed) deflate blocks.
static int write_png(const char *path, const uint8_t *rgb, int w, int h)
{
	FILE *f = fopen(path, "wb");
	if (!f)
		return 1;
	static const uint8_t sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
	fwrite(sig, 1, 8, f);
	uint8_t ihdr[13];
	put32(ihdr, w);
	put32(ihdr + 4, h);
	ihdr[8] = 8, ihdr[9] = 2, ihdr[10] = 0, ihdr[11] = 0, ihdr[12] = 0;
	png_chunk(f, "IHDR", ihdr, 13);

	size_t row = (size_t)w * 3 + 1, raw_len = row * h;
	uint8_t *raw = malloc(raw_len);
	for (int y = 0; y < h; y++) {
		raw[y * row] = 0;
		memcpy(raw + y * row + 1, rgb + (size_t)y * w * 3, (size_t)w * 3);
	}
	size_t blocks = (raw_len + 65534) / 65535;
	size_t z_len = 2 + raw_len + blocks * 5 + 4;
	uint8_t *z = malloc(z_len), *p = z;
	*p++ = 0x78, *p++ = 0x01;
	uint32_t a = 1, b = 0;
	for (size_t off = 0; off < raw_len;) {
		size_t n = raw_len - off > 65535 ? 65535 : raw_len - off;
		*p++ = off + n == raw_len;
		*p++ = n & 0xff, *p++ = n >> 8, *p++ = ~n & 0xff, *p++ = (~n >> 8) & 0xff;
		memcpy(p, raw + off, n);
		for (size_t i = 0; i < n; i++)
			a = (a + raw[off + i]) % 65521, b = (b + a) % 65521;
		p += n, off += n;
	}
	put32(p, (b << 16) | a);
	png_chunk(f, "IDAT", z, z_len);
	png_chunk(f, "IEND", NULL, 0);
	free(raw), free(z);
	return fclose(f) != 0;
}

// -------------------------------------------------------------------------
// runner configuration

static struct {
	char model[16], crtc[16];
	long frames;
	char output_dir[PATH_MAX];
	char disk_a[PATH_MAX], disk_b[PATH_MAX], rom[PATH_MAX], input[PATH_MAX];
	long audio_frames;
} args;

// -------------------------------------------------------------------------
// audio capture: CPCEC queues one frame of 16-bit stereo audio per frame.

static uint8_t *audio_ring;
static size_t audio_ring_size, audio_ring_pos, audio_ring_fill;

static int runner_queue_audio(SDL_AudioDeviceID dev, const void *data, Uint32 len)
{
	(void)dev;
	if (!audio_ring)
		return 0;
	const uint8_t *p = data;
	for (Uint32 i = 0; i < len; i++) {
		audio_ring[audio_ring_pos] = p[i];
		audio_ring_pos = (audio_ring_pos + 1) % audio_ring_size;
	}
	audio_ring_fill = audio_ring_fill + len > audio_ring_size ? audio_ring_size : audio_ring_fill + len;
	return 0;
}

static void put_le(FILE *f, uint32_t v, int bytes)
{
	for (int i = 0; i < bytes; i++)
		fputc((v >> (8 * i)) & 0xff, f);
}

static int write_wav(const char *path)
{
	FILE *f = fopen(path, "wb");
	if (!f)
		return 1;
	uint32_t n = audio_ring_fill;
	fwrite("RIFF", 1, 4, f), put_le(f, 36 + n, 4), fwrite("WAVEfmt ", 1, 8, f);
	put_le(f, 16, 4), put_le(f, 1, 2), put_le(f, AUDIO_CHANNELS, 2), put_le(f, AUDIO_PLAYBACK, 4);
	put_le(f, AUDIO_PLAYBACK * AUDIO_BYTESTEP, 4), put_le(f, AUDIO_BYTESTEP, 2), put_le(f, 16, 2);
	fwrite("data", 1, 4, f), put_le(f, n, 4);
	size_t start = (audio_ring_pos + audio_ring_size - n) % audio_ring_size;
	for (uint32_t i = 0; i < n; i++)
		fputc(audio_ring[(start + i) % audio_ring_size], f);
	return fclose(f) != 0;
}

static void die(const char *fmt, const char *arg)
{
	fprintf(stderr, "cpc-runner-cpcec: ");
	fprintf(stderr, fmt, arg);
	fputc('\n', stderr);
	_exit(2);
}

static void absolute(char *dst, const char *src)
{
	if (!realpath(src, dst))
		die("cannot resolve path %s", src);
}

static int copy_file(const char *from, const char *to)
{
	FILE *in = fopen(from, "rb");
	if (!in)
		return 1;
	FILE *out = fopen(to, "wb");
	if (!out)
		return fclose(in), 1;
	char buf[65536];
	size_t n;
	while ((n = fread(buf, 1, sizeof buf, in)) > 0)
		fwrite(buf, 1, n, out);
	fclose(in);
	return fclose(out) != 0;
}

// -------------------------------------------------------------------------
// input script

struct keyname {
	const char *name;
	int code; // CPC matrix line * 8 + bit
};

// Key names shared by every cpc-validation runner (see schema/runner-protocol.md).
static const struct keyname key_names[] = {
	{"ArrowUp", 0x00}, {"ArrowRight", 0x01}, {"ArrowDown", 0x02}, {"Numpad9", 0x03},
	{"Numpad6", 0x04}, {"Numpad3", 0x05}, {"NumpadEnter", 0x06}, {"NumpadPeriod", 0x07},
	{"ArrowLeft", 0x08}, {"Copy", 0x09}, {"Numpad7", 0x0a}, {"Numpad8", 0x0b},
	{"Numpad5", 0x0c}, {"Numpad1", 0x0d}, {"Numpad2", 0x0e}, {"Numpad0", 0x0f},
	{"Clear", 0x10}, {"BracketLeft", 0x11}, {"Enter", 0x12}, {"BracketRight", 0x13},
	{"Numpad4", 0x14}, {"Shift", 0x15}, {"Backslash", 0x16}, {"Control", 0x17},
	{"Caret", 0x18}, {"Minus", 0x19}, {"At", 0x1a}, {"P", 0x1b},
	{"Semicolon", 0x1c}, {"Colon", 0x1d}, {"Slash", 0x1e}, {"Period", 0x1f},
	{"Key0", 0x20}, {"Key9", 0x21}, {"O", 0x22}, {"I", 0x23},
	{"L", 0x24}, {"K", 0x25}, {"M", 0x26}, {"Comma", 0x27},
	{"Key8", 0x28}, {"Key7", 0x29}, {"U", 0x2a}, {"Y", 0x2b},
	{"H", 0x2c}, {"J", 0x2d}, {"N", 0x2e}, {"Space", 0x2f},
	{"Key6", 0x30}, {"Key5", 0x31}, {"R", 0x32}, {"T", 0x33},
	{"G", 0x34}, {"F", 0x35}, {"B", 0x36}, {"V", 0x37},
	{"Key4", 0x38}, {"Key3", 0x39}, {"E", 0x3a}, {"W", 0x3b},
	{"S", 0x3c}, {"D", 0x3d}, {"C", 0x3e}, {"X", 0x3f},
	{"Key1", 0x40}, {"Key2", 0x41}, {"Escape", 0x42}, {"Q", 0x43},
	{"Tab", 0x44}, {"A", 0x45}, {"CapsLock", 0x46}, {"Z", 0x47},
	{"JoystickUp", 0x48}, {"JoystickDown", 0x49}, {"JoystickLeft", 0x4a}, {"JoystickRight", 0x4b},
	{"JoystickFire1", 0x4c}, {"JoystickFire2", 0x4d}, {"JoystickFire3", 0x4e}, {"Delete", 0x4f},
};

static int key_code(const char *name)
{
	for (size_t i = 0; i < sizeof(key_names) / sizeof(*key_names); i++)
		if (!strcmp(key_names[i].name, name))
			return key_names[i].code;
	return -1;
}

// Returns the matrix code for a typed character and whether Shift is needed.
static int char_key(int c, int *shift)
{
	static const char *const unshifted = " \n:;,.-/@^[]\\";
	static const char *const unshifted_names[] = {
		"Space", "Enter", "Colon", "Semicolon", "Comma", "Period", "Minus",
		"Slash", "At", "Caret", "BracketLeft", "BracketRight", "Backslash"};
	static const char *const shifted = "!\"#$%&'()_=+*?><|{}";
	static const char *const shifted_names[] = {
		"Key1", "Key2", "Key3", "Key4", "Key5", "Key6", "Key7", "Key8", "Key9",
		"Key0", "Minus", "Semicolon", "Colon", "Slash", "Period", "Comma", "At",
		"BracketLeft", "BracketRight"};
	char name[8];
	*shift = 0;
	if (c >= 'A' && c <= 'Z')
		*shift = 1;
	else if (c >= 'a' && c <= 'z')
		c -= 32;
	if (c >= 'A' && c <= 'Z')
		return name[0] = c, name[1] = 0, key_code(name);
	if (c >= '0' && c <= '9')
		return snprintf(name, sizeof name, "Key%c", c), key_code(name);
	const char *p;
	if (c && (p = strchr(unshifted, c)))
		return key_code(unshifted_names[p - unshifted]);
	if (c && (p = strchr(shifted, c)))
		return *shift = 1, key_code(shifted_names[p - shifted]);
	return -1;
}

enum op_kind { OP_SLEEP, OP_PRESS, OP_RELEASE };

struct op {
	enum op_kind kind;
	int value; // frames for OP_SLEEP, matrix code otherwise
};

static struct op *ops;
static size_t op_count, op_cap, op_next;
static long sleep_left, input_frames;

static void push_op(enum op_kind kind, int value)
{
	if (op_count == op_cap)
		ops = realloc(ops, (op_cap = op_cap ? op_cap * 2 : 64) * sizeof *ops);
	ops[op_count].kind = kind, ops[op_count++].value = value;
}

// type_text holds each key for 2 frames and then releases it for 2 frames.
// The two-character sequence \n types Enter.
static void push_text(const char *text)
{
	for (; *text; text++) {
		int c = (unsigned char)*text;
		if (c == '\\' && text[1] == 'n')
			c = '\n', text++;
		int shift, code = char_key(c, &shift);
		if (code < 0) {
			fprintf(stderr, "type_text: skipping unsupported char %c\n", *text);
			continue;
		}
		if (shift)
			push_op(OP_PRESS, 0x15);
		push_op(OP_PRESS, code);
		push_op(OP_SLEEP, 2);
		push_op(OP_RELEASE, code);
		if (shift)
			push_op(OP_RELEASE, 0x15);
		push_op(OP_SLEEP, 2);
	}
}

static void load_input(const char *path)
{
	FILE *f = fopen(path, "r");
	if (!f)
		die("cannot read input script %s", path);
	char line[4096];
	while (fgets(line, sizeof line, f)) {
		size_t n = strlen(line);
		while (n && (line[n - 1] == '\n' || line[n - 1] == '\r'))
			line[--n] = 0;
		char *s = line;
		while (*s == ' ' || *s == '\t')
			s++;
		if (!*s || *s == '#')
			continue;
		if (!strncmp(s, "sleep ", 6))
			push_op(OP_SLEEP, atoi(s + 6));
		else if (!strncmp(s, "type_text ", 10))
			push_text(s + 10);
		else if (!strncmp(s, "key_press ", 10) || !strncmp(s, "key_release ", 12)) {
			int press = s[4] == 'p';
			char *name = s + (press ? 10 : 12);
			char *end = name + strlen(name);
			while (end > name && (end[-1] == ' ' || end[-1] == '\t'))
				*--end = 0;
			int code = key_code(name);
			if (code < 0)
				fprintf(stderr, "input script: unknown key %s\n", name);
			else
				push_op(press ? OP_PRESS : OP_RELEASE, code);
		} else
			fprintf(stderr, "input script: unknown directive %s\n", s);
	}
	fclose(f);
}

// Executes zero-length operations until the script needs frames to pass.
// Returns nonzero while the script is still running.
static int advance_script(void)
{
	while (!sleep_left && op_next < op_count) {
		struct op *o = &ops[op_next++];
		switch (o->kind) {
		case OP_SLEEP:
			sleep_left = o->value;
			break;
		case OP_PRESS:
			kbd_bit_set(o->value);
			break;
		case OP_RELEASE:
			kbd_bit_res(o->value);
			break;
		}
	}
	return sleep_left > 0;
}

// -------------------------------------------------------------------------
// artefacts

static void write_artefacts(long frames_run)
{
	if (mkdir(args.output_dir, 0777) && errno != EEXIST)
		die("cannot create %s", args.output_dir);
	char path[PATH_MAX + 32];

	// Map CPCEC's palette back to hardware colours, then emit canonical RGB.
	uint8_t *rgb = malloc((size_t)CANON_W * CANON_H * 3);
	int unknown = 0;
	for (int y = 0; y < CANON_H; y++) {
		VIDEO_UNIT *src = &video_frame[(VIDEO_OFFSET_Y + y) * VIDEO_LENGTH_X + VIDEO_OFFSET_X];
		uint8_t *dst = rgb + (size_t)y * CANON_W * 3;
		for (int x = 0; x < CANON_W; x++, dst += 3) {
			VIDEO_UNIT p = src[x];
			int hw = -1;
			for (int i = 0; i < 32; i++)
				if (video_xlat[i] == p) {
					hw = i;
					break;
				}
			if (hw < 0) {
				unknown++;
				dst[0] = p >> 16, dst[1] = p >> 8, dst[2] = p;
			} else
				memcpy(dst, canon_palette[hw], 3);
		}
	}
	if (unknown)
		fprintf(stderr, "warning: %d pixels did not match a hardware colour\n", unknown);
	snprintf(path, sizeof path, "%s/screen.png", args.output_dir);
	if (write_png(path, rgb, CANON_W, CANON_H))
		die("cannot write %s", path);
	free(rgb);

	int ram_size = type_id >= 2 ? 0x20000 : 0x10000;
	snprintf(path, sizeof path, "%s/ram.bin", args.output_dir);
	FILE *f = fopen(path, "wb");
	if (!f || fwrite(mem_ram, 1, ram_size, f) != (size_t)ram_size || fclose(f))
		die("cannot write %s", path);

	snprintf(path, sizeof path, "%s/meta.json", args.output_dir);
	if (!(f = fopen(path, "w")))
		die("cannot write %s", path);
	fprintf(f,
		"{\n  \"model\": \"%s\",\n  \"crtc\": \"%s\",\n  \"frames_run\": %ld,\n"
		"  \"exit\": \"frames_complete\",\n  \"ram_size\": %d,\n  \"screen_mode\": %d,\n"
		"  \"screen\": { \"width\": %d, \"height\": %d },\n  \"screen_ma\": %d,\n"
		"  \"emulator\": \"cpcec\"\n}\n",
		args.model, args.crtc, frames_run, ram_size, gate_mcr & 3, CANON_W, CANON_H,
		(crtc_table[12] << 8) | crtc_table[13]);
	if (fclose(f))
		die("cannot write %s", path);

	if (audio_ring) {
		snprintf(path, sizeof path, "%s/audio.wav", args.output_dir);
		if (write_wav(path))
			die("cannot write %s", path);
	}
}

// -------------------------------------------------------------------------
// per-frame hook

static long frames_done = -1;
static int script_done;
static int last_frame_id;

static int runner_poll(SDL_Event *event)
{
	(void)event;
	if (frames_done >= 0 && last_frame_id == video_pos_z)
		return 0; // not a new frame (video_pos_z counts completed frames)
	last_frame_id = video_pos_z;
	if (frames_done < 0) {
		// First call: the machine is set up but has not run yet.
		if (*args.rom) {
			FILE *f = fopen(args.rom, "rb");
			if (!f)
				die("cannot read --rom %s", args.rom);
			size_t n = fread1(mem_rom, 1 << 15, f);
			fclose(f);
			if (n != (1 << 14) && n != (1 << 15))
				die("--rom %s must be 16K or 32K", args.rom);
		}
		// Disks are opened from writable copies so software can write to
		// them without touching the fixtures.
		static const char *const copies[2] = {"disk-a.dsk", "disk-b.dsk"};
		const char *disks[2] = {args.disk_a, args.disk_b};
		for (int d = 0; d < 2; d++) {
			if (!*disks[d])
				continue;
			char copy[PATH_MAX + 16];
			snprintf(copy, sizeof copy, "%s/%s", args.output_dir, copies[d]);
			if (copy_file(disks[d], copy) || disc_open(copy, d, 1))
				die("cannot open disk %s", disks[d]);
		}
		frames_done = 0;
	} else {
		frames_done++;
		if (sleep_left)
			sleep_left--;
	}
	if (!script_done && !advance_script() && op_next >= op_count)
		script_done = 1, input_frames = frames_done;
	if (script_done && frames_done - input_frames >= args.frames) {
		write_artefacts(frames_done);
		fflush(NULL);
		_exit(0);
	}
	return 0;
}

// -------------------------------------------------------------------------

static const char *opt_value(int *i, int argc, char **argv)
{
	if (*i + 1 >= argc)
		die("missing value for %s", argv[*i]);
	return argv[++*i];
}

int main(int argc, char **argv)
{
	crc_init();
	args.frames = -1;
	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		if (!strcmp(a, "--model"))
			snprintf(args.model, sizeof args.model, "%s", opt_value(&i, argc, argv));
		else if (!strcmp(a, "--crtc"))
			snprintf(args.crtc, sizeof args.crtc, "%s", opt_value(&i, argc, argv));
		else if (!strcmp(a, "--frames"))
			args.frames = atol(opt_value(&i, argc, argv));
		else if (!strcmp(a, "--output-dir"))
			snprintf(args.output_dir, sizeof args.output_dir, "%s", opt_value(&i, argc, argv));
		else if (!strcmp(a, "--disk-a"))
			absolute(args.disk_a, opt_value(&i, argc, argv));
		else if (!strcmp(a, "--disk-b"))
			absolute(args.disk_b, opt_value(&i, argc, argv));
		else if (!strcmp(a, "--rom"))
			absolute(args.rom, opt_value(&i, argc, argv));
		else if (!strcmp(a, "--input"))
			absolute(args.input, opt_value(&i, argc, argv));
		else if (!strcmp(a, "--audio-frames"))
			args.audio_frames = atol(opt_value(&i, argc, argv));
		else
			fprintf(stderr, "ignoring unknown flag %s\n", a);
	}
	if (!*args.model || !*args.crtc || args.frames < 0 || !*args.output_dir)
		die("usage: %s --model M --crtc C --frames N --output-dir DIR [...]", argv[0]);

	const char *model_flag, *ram_flag, *disc_flag;
	if (!strcmp(args.model, "Cpc464"))
		model_flag = "-m0", ram_flag = "-k0", disc_flag = "-X";
	else if (!strcmp(args.model, "Cpc664"))
		model_flag = "-m1", ram_flag = "-k0", disc_flag = "-x";
	else if (!strcmp(args.model, "Cpc6128"))
		model_flag = "-m2", ram_flag = "-k1", disc_flag = "-x";
	else
		die("unknown model %s", args.model);
	if (!strcmp(args.model, "Cpc464") && (*args.disk_a || *args.disk_b))
		disc_flag = "-x"; // a 464 with a DDI-1 interface

	const char *crtc_flag;
	if (!strcmp(args.crtc, "Type0"))
		crtc_flag = "-g0";
	else if (!strcmp(args.crtc, "Type1"))
		crtc_flag = "-g1";
	else if (!strcmp(args.crtc, "Type2"))
		crtc_flag = "-g2";
	else if (!strcmp(args.crtc, "Type4"))
		crtc_flag = "-g4";
	else
		die("unknown crtc %s", args.crtc);

	if (*args.input)
		load_input(args.input);
	if (mkdir(args.output_dir, 0777) && errno != EEXIST)
		die("cannot create %s", args.output_dir);

	// CPCEC finds its ROMs (and an optional config file) next to argv[0].
	// The build directory holds copies of CPCEC's ROMs and no config file.
	char self[PATH_MAX];
	ssize_t n = readlink("/proc/self/exe", self, sizeof self - 1);
	if (n <= 0)
		die("cannot locate %s", "/proc/self/exe");
	self[n] = 0;

	SDL_setenv("SDL_VIDEODRIVER", "dummy", 1);
	SDL_setenv("SDL_AUDIODRIVER", "dummy", 1);

	// Sound is only generated when audio is requested (-s on, -t stereo).
	const char *sound_flag = "-S";
	if (args.audio_frames > 0) {
		sound_flag = "-st";
		audio_ring_size = (size_t)args.audio_frames * (AUDIO_PLAYBACK / 50) * AUDIO_BYTESTEP;
		audio_ring = calloc(1, audio_ring_size);
	}
	char *cpcec_argv[] = {self, (char *)model_flag, (char *)ram_flag, (char *)crtc_flag,
		(char *)disc_flag, (char *)sound_flag, "-O", "-c0", "-C0", "-J", "-!", NULL};
	return cpcec_main(sizeof cpcec_argv / sizeof *cpcec_argv - 1, cpcec_argv);
}
