//! Ronald adapter implementing the cpc-validation runner protocol.

use std::path::PathBuf;

use clap::Parser;
use ronald_core::{
    AudioSink, Driver, VideoSink,
    constants::{SCREEN_BUFFER_HEIGHT, SCREEN_BUFFER_WIDTH},
    system::{CpcModel, CrtcType, DiskDrives, SystemConfig},
};

const FRAME_MICROSECONDS: usize = 20_000; // 50 Hz

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
}

struct CaptureVideo {
    last: Vec<u8>,
}

impl VideoSink for CaptureVideo {
    fn draw_frame(&mut self, buffer: &Vec<u8>) {
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

    if args.rom.is_some() {
        eprintln!("--rom not yet supported by this adapter");
        std::process::exit(2);
    }

    let config = SystemConfig {
        model,
        crtc,
        disk_drives: DiskDrives::One,
    };
    let mut driver = Driver::with_config(&config);

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

    image::save_buffer(
        args.output_dir.join("screen.png"),
        &video.last,
        SCREEN_BUFFER_WIDTH as u32,
        SCREEN_BUFFER_HEIGHT as u32,
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
        "screen": { "width": SCREEN_BUFFER_WIDTH, "height": SCREEN_BUFFER_HEIGHT },
    });
    std::fs::write(
        args.output_dir.join("meta.json"),
        serde_json::to_string_pretty(&meta).unwrap(),
    )
    .expect("write meta.json");
}
