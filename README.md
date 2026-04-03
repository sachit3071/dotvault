# ⚡ dotvault

A minimal, portable setup for your terminal environment.

`dotvault` helps you keep your aliases, functions, and small utilities in one place and sync them across machines.

Instead of cluttering your .bashrc or .zshrc, everything lives here — clean, modular, and version-controlled.

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

dotvault/
  functions/
    git-aliases
    ...

You can keep adding:
- more alias files
- reusable shell functions
- scripts for automation

---

## ⚙️ Setup (2 steps)

### 1️⃣ Clone the repo
```
git clone <your-repo-url> ~/dotvault
```
---

### 2️⃣ Link it to your shell

#### Linux (bash)
echo '
# Load dotvault
```
if [ -d ~/dotvault ]; then
  for file in ~/dotvault/*; do
    [ -f "$file" ] && source "$file"
  done
fi
' >> ~/.bashrc && source ~/.bashrc
```
---

#### macOS (zsh)
echo '
# Load dotvault
```
if [ -d ~/dotvault ]; then
  for file in ~/dotvault/*; do
    [ -f "$file" ] && source "$file"
  done
fi
' >> ~/.zshrc && source ~/.zshrc
```
---

## 🧠 How it works

- Your shell (.bashrc / .zshrc) loads all files inside dotvault/functions
- Each file can contain:
  - aliases
  - functions
  - environment variables

This keeps your main config file clean and makes everything reusable.

---

## 🔧 Extending dotvault

You can add your own files like:

functions/
  docker-aliases
  kubernetes
  utils

Or even define functions:

mkcd() {
  mkdir -p "$1" && cd "$1"
}

---

## 💡 Why use this?

- Same setup across all machines
- No messy .bashrc
- Easy backup via Git
- Modular & scalable
- Faster workflow

---

## 🔄 Updating

cd ~/dotvault
git pull

No extra setup needed.

---

## 🧩 Future Ideas

- Bootstrap script (one-command setup)
- OS-specific configs
- Auto-install tools
- Advanced CLI helpers

---

## 🏁 Philosophy

Keep your environment portable, minimal, and powerful.