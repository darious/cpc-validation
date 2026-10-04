//! Ronald adapter implementing the cpc-validation runner protocol.

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use clap::Parser;
use ronald_core::{
    AudioSink, Driver, VideoSink,
    constants::{SCREEN_BUFFER_HEIGHT, SCREEN_BUFFER_WIDTH},
    system::{CpcModel, CrtcType, DiskDrives, SystemConfig, memory::RomSlot},
};

const FRAME_MICROSECONDS: usize = 20_000; // 50 Hz

// The canonical screen window inside Ronald's frame buffer.
const CANONICAL_TOP: usize = 4;
const CANONICAL_HEIGHT: usize = 536;

#[derive(Parser)]
#[command(author, version, about = "Ronald CPC emulator adapter")]
struct Args {
    #[arg(long)]
    model: String,
    #[arg(long)]
    crtc: String,
    #[arg(long)]
    frames: usize,
    #[arg(long)]
    output_dir: PathBuf,
    #[arg(long)]
    disk_a: Option<PathBuf>,
    #[arg(long)]
    disk_b: Option<PathBuf>,
    #[arg(long, value_name = "ROM_PATH")]
    rom: Option<PathBuf>,
    #[arg(long)]
    input: Option<PathBuf>,
    /// Directory holding cpc464.rom, cpc664.rom, cpc6128.rom (32K OS+BASIC)
    /// and amsdos.rom. Defaults to $RONALD_ROM_DIR, then the executable's
    /// directory, then the current directory.
    #[arg(long)]
    rom_dir: Option<PathBuf>,
}

struct CaptureVideo {
    last: Vec<u8>,
}

impl VideoSink for CaptureVideo {
    fn draw_frame(&mut self, buffer: &[u8]) {
        self.last.clear();
        self.last.extend_from_slice(buffer);
    }
}

struct NullAudio;

impl AudioSink for NullAudio {
    fn get_sample_rate(&self) -> Option<f32> {
        None
    }
    fn play_audio(&self) {}
    fn pause_audio(&self) {}
    fn add_sample(&self, _sample: f32) {}
}

fn parse_model(s: &str) -> Result<CpcModel, String> {
    match s {
        "Cpc464" => Ok(CpcModel::Cpc464),
        "Cpc664" => Ok(CpcModel::Cpc664),
        "Cpc6128" => Ok(CpcModel::Cpc6128),
        _ => Err(format!("unknown model {s}")),
    }
}

fn parse_crtc(s: &str) -> Result<CrtcType, String> {
    match s {
        "Type0" => Ok(CrtcType::Type0),
        "Type1" => Ok(CrtcType::Type1),
        "Type2" => Ok(CrtcType::Type2),
        "Type4" => Ok(CrtcType::Type4),
        _ => Err(format!("unknown crtc {s}")),
    }
}

fn find_rom_dir(args: &Args, probe: &str) -> PathBuf {
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Some(dir) = &args.rom_dir {
        candidates.push(dir.clone());
    }
    if let Ok(dir) = std::env::var("RONALD_ROM_DIR") {
        candidates.push(PathBuf::from(dir));
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            candidates.push(dir.to_path_buf());
        }
    }
    candidates.push(PathBuf::from("."));
    candidates
        .into_iter()
        .find(|d| d.join(probe).exists())
        .unwrap_or_else(|| PathBuf::from("."))
}

fn read_rom(path: &Path) -> Result<Vec<u8>, String> {
    std::fs::read(path).map_err(|e| format!("read {}: {e}", path.display()))
}

/// Builds the ROM set for the model: the 32K OS+BASIC image split into the
/// lower ROM and upper ROM 0, AMSDOS as upper ROM 7 on the 664/6128 (or when
/// a disk is inserted), and an optional --rom lower ROM replacement.
fn load_roms(args: &Args, model: CpcModel) -> Result<HashMap<RomSlot, Vec<u8>>, String> {
    let file = match model {
        CpcModel::Cpc464 => "cpc464.rom",
        CpcModel::Cpc664 => "cpc664.rom",
        CpcModel::Cpc6128 => "cpc6128.rom",
    };
    let dir = find_rom_dir(args, file);
    let system = read_rom(&dir.join(file))?;
    if system.len() != 0x8000 {
        return Err(format!("{file} must be 32K"));
    }
    let mut roms = HashMap::new();
    roms.insert(RomSlot::Lower, system[..0x4000].to_vec());
    roms.insert(RomSlot::Upper(0), system[0x4000..].to_vec());
    let disks = args.disk_a.is_some() || args.disk_b.is_some();
    if model != CpcModel::Cpc464 || disks {
        roms.insert(RomSlot::Upper(7), read_rom(&dir.join("amsdos.rom"))?);
    }
    if let Some(path) = &args.rom {
        let data = read_rom(path)?;
        match data.len() {
            0x4000 => {
                roms.insert(RomSlot::Lower, data);
            }
            0x8000 => {
                roms.insert(RomSlot::Lower, data[..0x4000].to_vec());
                roms.insert(RomSlot::Upper(0), data[0x4000..].to_vec());
            }
            _ => return Err("--rom must be 16K or 32K".to_string()),
        }
    }
    Ok(roms)
}

fn step_frames(
    driver: &mut Driver,
    video: &mut CaptureVideo,
    audio: &mut NullAudio,
    frames: usize,
) {
    for _ in 0..frames {
        driver.step(FRAME_MICROSECONDS, video, audio);
    }
}

fn type_char(driver: &mut Driver, video: &mut CaptureVideo, audio: &mut NullAudio, c: char) {
    let (key, shift) = match c {
        'A'..='Z' => (c.to_string(), false),
        'a'..='z' => (c.to_ascii_uppercase().to_string(), false),
        '0'..='9' => (format!("Key{c}"), false),
        ' ' => ("Space".to_string(), false),
        '\n' => ("Enter".to_string(), false),
        '"' => ("Key2".to_string(), true),
        ':' => ("Colon".to_string(), false),
        ';' => ("Semicolon".to_string(), false),
        ',' => ("Comma".to_string(), false),
        '.' => ("Period".to_string(), false),
        '-' => ("Minus".to_string(), false),
        '/' => ("Slash".to_string(), false),
        '@' => ("At".to_string(), false),
        '^' => ("Caret".to_string(), false),
        '[' => ("BracketLeft".to_string(), false),
        ']' => ("BracketRight".to_string(), false),
        '\\' => ("Backslash".to_string(), false),
        '!' => ("Key1".to_string(), true),
        '#' => ("Key3".to_string(), true),
        '$' => ("Key4".to_string(), true),
        '%' => ("Key5".to_string(), true),
        '&' => ("Key6".to_string(), true),
        '\'' => ("Key7".to_string(), true),
        '(' => ("Key8".to_string(), true),
        ')' => ("Key9".to_string(), true),
        _ => {
            eprintln!("type_text: skipping unsupported char {c:?}");
            return;
        }
    };

    if shift {
        driver.press_key("Shift");
    }
    driver.press_key(&key);
    step_frames(driver, video, audio, 2);
    driver.release_key(&key);
    if shift {
        driver.release_key("Shift");
    }
    step_frames(driver, video, audio, 1);
}

fn run_input_script(
    driver: &mut Driver,
    video: &mut CaptureVideo,
    audio: &mut NullAudio,
    script: &str,
) -> usize {
    let mut frames_used = 0usize;
    for raw in script.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("sleep ") {
            if let Ok(n) = rest.trim().parse::<usize>() {
                step_frames(driver, video, audio, n);
                frames_used += n;
            }
        } else if let Some(rest) = line.strip_prefix("type_text ") {
            let text = rest;
            for c in text.chars() {
                type_char(driver, video, audio, c);
                frames_used += 3;
            }
        } else if let Some(rest) = line.strip_prefix("key_press ") {
            driver.press_key(rest.trim());
        } else if let Some(rest) = line.strip_prefix("key_release ") {
            driver.release_key(rest.trim());
        } else {
            eprintln!("input script: unknown directive {line:?}");
        }
    }
    frames_used
}

fn main() {
    let args = Args::parse();

    let model = match parse_model(&args.model) {
        Ok(m) => m,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };
    let crtc = match parse_crtc(&args.crtc) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };

    let roms = match load_roms(&args, model) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(2);
        }
    };

    let config = SystemConfig {
        model,
        crtc,
        disk_drives: DiskDrives::One,
        roms,
    };
    let mut driver = Driver::with_config(config);

    let mut video = CaptureVideo {
        last: vec![0u8; SCREEN_BUFFER_WIDTH * SCREEN_BUFFER_HEIGHT * 4],
    };
    let mut audio = NullAudio;

    // Always run one warmup frame so the framebuffer is populated even when --frames is 0.
    step_frames(&mut driver, &mut video, &mut audio, 1);

    if let Some(path) = args.disk_a.as_ref() {
        let data = std::fs::read(path).expect("read --disk-a");
        driver.load_disk(0, data, path.clone());
    }
    if let Some(path) = args.disk_b.as_ref() {
        let data = std::fs::read(path).expect("read --disk-b");
        driver.load_disk(1, data, path.clone());
    }

    let mut input_frames = 0usize;
    if let Some(path) = args.input.as_ref() {
        let script = std::fs::read_to_string(path).expect("read --input");
        input_frames = run_input_script(&mut driver, &mut video, &mut audio, &script);
    }

    step_frames(&mut driver, &mut video, &mut audio, args.frames);

    std::fs::create_dir_all(&args.output_dir).expect("create --output-dir");

    // Crop Ronald's 768x560 frame to the canonical 768x536 window shared by
    // all runners (see schema/runner-protocol.md).
    let row = SCREEN_BUFFER_WIDTH * 4;
    let canonical = &video.last[CANONICAL_TOP * row..(CANONICAL_TOP + CANONICAL_HEIGHT) * row];
    image::save_buffer(
        args.output_dir.join("screen.png"),
        canonical,
        SCREEN_BUFFER_WIDTH as u32,
        CANONICAL_HEIGHT as u32,
        image::ColorType::Rgba8,
    )
    .expect("save screen.png");

    let dbg = driver.debug_view();
    let ram = dbg.memory.composite_ram.clone();
    let screen_mode = dbg.gate_array.current_screen_mode;

    std::fs::write(args.output_dir.join("ram.bin"), &ram).expect("write ram.bin");

    let meta = serde_json::json!({
        "model": args.model,
        "crtc": args.crtc,
        "frames_run": 1 + input_frames + args.frames,
        "exit": "frames_complete",
        "ram_size": ram.len(),
        "screen_mode": screen_mode,
        "screen": { "width": SCREEN_BUFFER_WIDTH, "height": CANONICAL_HEIGHT },
        "emulator": "ronald",
    });
    std::fs::write(
        args.output_dir.join("meta.json"),
        serde_json::to_string_pretty(&meta).unwrap(),
    )
    .expect("write meta.json");
}
