// Minimal Luau runner: `luaurun check <files...>` compiles each file (syntax check);
// `luaurun run <file> [args...]` executes a script with `readfile`, `writefile`, `ARGS` and `print` available.
use mlua::{Lua, Value};
use std::fs;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: luaurun check <files...> | run <file> [args...]");
        std::process::exit(2);
    }
    let lua = Lua::new();
    let mode = args[1].as_str();
    if mode == "check" {
        let mut failed = false;
        for f in &args[2..] {
            let src = fs::read_to_string(f).expect("read");
            match lua.load(&src).set_name(f.as_str()).into_function() {
                Ok(_) => {}
                Err(e) => { eprintln!("{}", e); failed = true; }
            }
        }
        std::process::exit(if failed { 1 } else { 0 });
    }
    let globals = lua.globals();
    let readfile = lua.create_function(|_, p: String| Ok(fs::read_to_string(&p).ok())).unwrap();
    globals.set("readfile", readfile).unwrap();
    let writefile = lua.create_function(|_, (p, s): (String, String)| { fs::write(&p, s).map_err(mlua::Error::external)?; Ok(()) }).unwrap();
    globals.set("writefile", writefile).unwrap();
    let t = lua.create_table().unwrap();
    for (i, a) in args[3..].iter().enumerate() { t.set(i + 1, a.clone()).unwrap(); }
    globals.set("ARGS", t).unwrap();
    let clock = lua.create_function(|_, ()| Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_secs_f64())).unwrap();
    globals.set("os_clock", clock).unwrap();
    let loadchunk = lua.create_function(|lua, (src, name, env): (String, String, mlua::Table)| {
        let f = lua.load(&src).set_name(name).set_environment(env).into_function()?;
        Ok(f)
    }).unwrap();
    globals.set("loadchunk", loadchunk).unwrap();
    let listdir = lua.create_function(|lua, p: String| {
        let t = lua.create_table()?;
        let mut names: Vec<String> = Vec::new();
        if let Ok(rd) = fs::read_dir(&p) {
            for e in rd.flatten() {
                let name = e.file_name().to_string_lossy().to_string();
                let is_dir = e.file_type().map(|t| t.is_dir()).unwrap_or(false);
                names.push(if is_dir { format!("{}/", name) } else { name });
            }
        }
        names.sort();
        for (i, n) in names.into_iter().enumerate() { t.set(i + 1, n)?; }
        Ok(t)
    }).unwrap();
    globals.set("listdir", listdir).unwrap();
    let f = &args[2];
    let src = fs::read_to_string(f).expect("read");
    lua.sandbox(false).ok();
    match lua.load(&src).set_name(f.as_str()).exec() {
        Ok(_) => {}
        Err(e) => { eprintln!("{}", e); std::process::exit(1); }
    }
    let _ = Value::Nil;
}
