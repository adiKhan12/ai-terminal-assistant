# 🤖 Terminal Assistant

AI-powered command line assistant that learns from your habits and helps you work faster.

## ✨ Features

### 🧠 AI-Powered Help
- Ask questions in natural language and get exact commands
- Context-aware suggestions based on your recent work
- Understands your SSH hosts and frequent commands

### 📚 Smart Command History
- Automatically logs every command you run
- Search through your command history
- Track which commands succeeded or failed
- Remember working directories for each command

### 🔐 SSH Management
- Auto-learns SSH hosts as you use them
- Tracks usage frequency and last used time
- Quick access to your frequently used servers

### 💡 Intelligent Suggestions
- Get command suggestions based on partial input
- Learn from your command patterns
- Context-aware recommendations

## 🚀 Installation

1. **Save the installation script:**
   ```bash
   curl -o install_ta.sh https://your-url/install.sh
   chmod +x install_ta.sh
   ```

2. **Run the installer:**
   ```bash
   ./install_ta.sh
   ```

3. **Restart your terminal or reload shell:**
   ```bash
   source ~/.zshrc
   ```

## 📖 Usage

### Ask AI for Help
```bash
# Natural language queries
tai "how do I find large files?"
tai "connect to my prod server"
tai "compress a directory with tar"
tai "what's the git command to undo last commit?"
```

### View Command History
```bash
# Show recent commands
ta history

# Or use the shortcut
tah
```

### Search History
```bash
# Find commands containing 'docker'
ta search docker

# Shortcut
tas docker
```

### SSH Hosts
```bash
# View all SSH hosts you've connected to
ta ssh

# Shows frequency and last used time
```

### Command Suggestions
```bash
# Get suggestions for partial commands
ta suggest git
ta suggest ssh
```

## 🎯 Real-World Examples

**Example 1: "I forgot that rsync command"**
```bash
tai "how do I sync files to remote server preserving permissions?"
```
Output:
```
COMMAND: rsync -avz --progress /local/path user@remote:/remote/path
EXPLANATION: -a preserves permissions/timestamps, -v verbose, -z compresses during transfer
```

**Example 2: "What was that server I connected to?"**
```bash
ta ssh
```
Output:
```
🔐 SSH Hosts (by usage):

  user@production.example.com
    Used 47 times | Last: 2025-10-06 14:23:11

  admin@staging.example.com
    Used 12 times | Last: 2025-10-05 09:15:42
```

**Example 3: "I need that docker command I used last week"**
```bash
tas docker compose
```
Output:
```
📝 Found 3 matching commands:

✓ docker compose up -d
   /home/user/project | 2025-10-01 10:23:45

✓ docker compose logs -f