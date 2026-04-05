# ⚡ dotvault

A minimal, portable setup for your terminal environment.

`dotvault` helps you keep your aliases, functions, and small utilities in one place and sync them across machines.

Instead of cluttering your `.bashrc` or `.zshrc`, everything lives here — clean, modular, and version-controlled.

---

## 🚀 What’s inside?

- Git aliases (faster workflows)
- Python environment shortcuts
- Custom shell functions (extendable)
- Modular structure (easy to scale)

This repo is not just aliases —
it also includes custom shell functions that behave like mini CLI tools.

---

## 📁 Structure
```
dotvault/
  git-aliases.sh
  docker-aliases.sh
  ...
```

You can keep adding:

- more alias files
- reusable shell functions
- scripts for automation

---

## ⚙️ Setup (2 steps)

### 1️⃣ Clone the repo
```bash
git clone https://github.com/sachit3071/dotvault.git ~/dotvault
```

---

### 2️⃣ Link it to your shell

Works on both **Linux (bash)** and **macOS (zsh)** — run this once:
```bash
SHELL_RC="$HOME/.bashrc"
[ -n "$ZSH_VERSION" ] && SHELL_RC="$HOME/.zshrc"
echo '
# Load dotvault
if [ -d ~/dotvault ]; then
  for file in ~/dotvault/*.sh; do
    [ -f "$file" ] && source "$file"
  done
fi
' >> "$SHELL_RC" && source "$SHELL_RC"
```

This auto-detects your shell and appends the loader to the right config file.

---

## 🧠 How it works

- Your shell (`.bashrc` / `.zshrc`) loads all `.sh` files inside `dotvault/`
- Each file can contain:
  - aliases
  - functions
  - environment variables

This keeps your main config file clean and makes everything reusable.

---

## 🔧 Extending dotvault

You can add your own files like:
```
dotvault/
  docker-aliases.sh
  kubernetes.sh
  utils.sh
```

Or even define functions:
```bash
mkcd() {
  mkdir -p "$1" && cd "$1"
}
```

---

## 💡 Why use this?

- Same setup across all machines
- No messy `.bashrc`
- Easy backup via Git
- Modular & scalable
- Faster workflow

---

## 🔄 Updating
```bash
cd ~/dotvault
git pull
```

No extra setup needed — your shell will pick up the changes on the next session (or `source` your shell config manually).

---

## 🧩 Future Ideas

- Bootstrap script (one-command setup)
- OS-specific configs
- Auto-install tools
- Advanced CLI helpers

---

## 🏁 Philosophy

Keep your environment portable, minimal, and powerful.