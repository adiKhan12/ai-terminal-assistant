#!/bin/bash
# Terminal Assistant Installation Script for Mac

set -e

echo "🤖 Installing Terminal Assistant..."

# Create directory
TA_DIR="$HOME/.terminal_assistant"
mkdir -p "$TA_DIR"

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed."
    echo "Install it with: brew install python3"
    exit 1
fi

echo "✓ Python 3 found"

# Install required Python packages
echo "📦 Installing Python dependencies..."
pip3 install requests --quiet

# Save the main Python script
cat > "$TA_DIR/ta.py" << 'EOFPYTHON'
#!/usr/bin/env python3
"""
Terminal Assistant - AI-powered command line helper
Learns from your command history and helps with suggestions
"""

import os
import sqlite3
import json
from datetime import datetime
from pathlib import Path
import subprocess
import sys

# DeepSeek API configuration
DEEPSEEK_API_KEY = "API_KEY"
DEEPSEEK_BASE_URL = "https://api.deepseek.com"

class TerminalAssistant:
    def __init__(self):
        self.db_path = Path.home() / ".terminal_assistant" / "commands.db"
        self.db_path.parent.mkdir(exist_ok=True)
        self.init_database()
    
    def init_database(self):
        """Initialize SQLite database for command history"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS command_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                command TEXT NOT NULL,
                working_directory TEXT,
                exit_code INTEGER,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                context TEXT,
                tags TEXT
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS ssh_hosts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                hostname TEXT UNIQUE NOT NULL,
                username TEXT,
                port INTEGER DEFAULT 22,
                key_path TEXT,
                last_used DATETIME,
                usage_count INTEGER DEFAULT 0
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS command_patterns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                pattern_name TEXT,
                commands TEXT,
                description TEXT,
                usage_count INTEGER DEFAULT 0
            )
        """)
        
        conn.commit()
        conn.close()
    
    def log_command(self, command, working_dir=None, exit_code=0, context=None):
        """Log a command to the database"""
        import time
        max_retries = 3
        
        for attempt in range(max_retries):
            try:
                conn = sqlite3.connect(self.db_path, timeout=10.0)
                cursor = conn.cursor()
                
                cursor.execute("""
                    INSERT INTO command_history (command, working_directory, exit_code, context)
                    VALUES (?, ?, ?, ?)
                """, (command, working_dir or os.getcwd(), exit_code, context))
                
                # Extract and store SSH hosts
                if command.strip().startswith('ssh'):
                    self._extract_ssh_info_safe(command, conn)
                
                conn.commit()
                conn.close()
                break
            except sqlite3.OperationalError as e:
                if attempt < max_retries - 1:
                    time.sleep(0.1)
                else:
                    pass  # Silent fail on last attempt
            except Exception:
                break

    def _extract_ssh_info_safe(self, command, conn=None):
        """Extract SSH info without opening new connection"""
        try:
            parts = command.strip().split()
            if len(parts) < 2:
                return
            
            target = parts[1] if not parts[1].startswith('-') else (parts[2] if len(parts) > 2 else None)
            if not target:
                return
            
            username = None
            hostname = target
            
            if '@' in hostname:
                username, hostname = hostname.split('@', 1)
            
            hostname = hostname.split(':')[0]
            
            should_close = False
            if conn is None:
                conn = sqlite3.connect(self.db_path, timeout=10.0)
                should_close = True
            
            cursor = conn.cursor()
            cursor.execute("SELECT usage_count FROM ssh_hosts WHERE hostname = ?", (hostname,))
            existing = cursor.fetchone()
            
            if existing:
                cursor.execute("""
                    UPDATE ssh_hosts 
                    SET username = ?, last_used = ?, usage_count = usage_count + 1
                    WHERE hostname = ?
                """, (username, datetime.now(), hostname))
            else:
                cursor.execute("""
                    INSERT INTO ssh_hosts (hostname, username, last_used, usage_count)
                    VALUES (?, ?, ?, 1)
                """, (hostname, username, datetime.now()))
            
            if should_close:
                conn.commit()
                conn.close()
        except Exception:
            pass
    
    def get_recent_commands(self, limit=50):
        """Get recent commands from history"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT command, working_directory, timestamp, exit_code
            FROM command_history
            ORDER BY timestamp DESC
            LIMIT ?
        """, (limit,))
        
        results = cursor.fetchall()
        conn.close()
        return results
    
    def search_commands(self, query):
        """Search command history"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT command, working_directory, timestamp, exit_code
            FROM command_history
            WHERE command LIKE ?
            ORDER BY timestamp DESC
            LIMIT 20
        """, (f"%{query}%",))
        
        results = cursor.fetchall()
        conn.close()
        return results
    
    def get_ssh_hosts(self):
        """Get all SSH hosts sorted by usage"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute("""
            SELECT hostname, username, usage_count, last_used
            FROM ssh_hosts
            ORDER BY usage_count DESC, last_used DESC
        """)
        
        results = cursor.fetchall()
        conn.close()
        return results
    
    def get_context_for_ai(self):
        """Get context to send to AI"""
        recent = self.get_recent_commands(20)
        ssh_hosts = self.get_ssh_hosts()
        
        context = {
            "recent_commands": [cmd[0] for cmd in recent],
            "working_directory": os.getcwd(),
            "ssh_hosts": [{"host": h[0], "user": h[1]} for h in ssh_hosts[:10]],
            "shell": os.environ.get("SHELL", "unknown")
        }
        return context
    
    def query_database(self, sql_query):
        """Execute SQL query on the database"""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute(sql_query)
            results = cursor.fetchall()
            conn.close()
            return results
        except Exception as e:
            return f"Error: {str(e)}"
    
    def ask_ai(self, user_query):
        """Ask AI for command suggestions using DeepSeek API"""
        import requests
        
        context = self.get_context_for_ai()
        
        system_prompt = f"""You are a helpful terminal assistant with access to the user's command history database.

DATABASE SCHEMA:
- command_history: id, command, working_directory, exit_code, timestamp, context, tags
- ssh_hosts: id, hostname, username, port, key_path, last_used, usage_count
- command_patterns: id, pattern_name, commands, description, usage_count

Current context:
- Working directory: {context['working_directory']}
- Recent commands: {', '.join(context['recent_commands'][:5])}
- Known SSH hosts: {', '.join([h['host'] for h in context['ssh_hosts'][:5]])}

When the user asks about their command history (e.g., "show my last 5 ssh connections", "what git commands did I run"), respond with:

SQL_QUERY: <the SQL query to run>
EXPLANATION: <what the query does>

For other general terminal questions, respond with:
COMMAND: <the actual command>
EXPLANATION: <brief explanation>

Examples:
User: "show me my last 5 ssh connections"
Response:
SQL_QUERY: SELECT command, timestamp FROM command_history WHERE command LIKE 'ssh %' ORDER BY timestamp DESC LIMIT 5
EXPLANATION: This queries your Terminal Assistant database to show the last 5 SSH commands you ran with timestamps.

User: "how do I compress a folder?"
Response:
COMMAND: tar -czf archive.tar.gz foldername
EXPLANATION: Creates a compressed tar archive of the folder.
"""
        
        try:
            response = requests.post(
                f"{DEEPSEEK_BASE_URL}/chat/completions",
                headers={
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {DEEPSEEK_API_KEY}"
                },
                json={
                    "model": "deepseek-chat",
                    "messages": [
                        {"role": "system", "content": system_prompt},
                        {"role": "user", "content": user_query}
                    ],
                    "stream": False
                }
            )
            
            if response.status_code == 200:
                result = response.json()
                ai_response = result['choices'][0]['message']['content']
                
                # Check if AI wants to query the database
                if "SQL_QUERY:" in ai_response:
                    # Extract SQL query
                    lines = ai_response.split('\n')
                    sql_query = None
                    for line in lines:
                        if line.startswith("SQL_QUERY:"):
                            sql_query = line.replace("SQL_QUERY:", "").strip()
                            break
                    
                    if sql_query:
                        # Execute the query
                        query_results = self.query_database(sql_query)
                        
                        # Format results
                        result_text = "\n📊 Query Results:\n\n"
                        if isinstance(query_results, str):
                            result_text += query_results
                        elif query_results:
                            for row in query_results:
                                result_text += f"  {' | '.join(str(item) for item in row)}\n"
                        else:
                            result_text += "  No results found\n"
                        
                        return ai_response + "\n" + result_text
                
                return ai_response
            else:
                return f"Error: API returned {response.status_code}"
        
        except Exception as e:
            return f"Error calling API: {str(e)}"
    
    def suggest_command(self, partial_command):
        """Suggest command based on history"""
        matches = self.search_commands(partial_command)
        if matches:
            return [cmd[0] for cmd in matches[:5]]
        return []


def main():
    assistant = TerminalAssistant()
    
    if len(sys.argv) < 2:
        print("Terminal Assistant - AI-powered command helper")
        print("\nUsage:")
        print("  ta ask 'your question'     - Ask AI for command help")
        print("  ta log <command>           - Log a command to history")
        print("  ta search <query>          - Search command history")
        print("  ta history                 - Show recent commands")
        print("  ta ssh                     - Show SSH hosts")
        print("  ta suggest <partial>       - Get command suggestions")
        return
    
    command = sys.argv[1]
    
    if command == "ask":
        if len(sys.argv) < 3:
            print("Usage: ta ask 'your question'")
            return
        query = ' '.join(sys.argv[2:])
        print(f"\n🤖 Thinking...\n")
        response = assistant.ask_ai(query)
        print(response)
    
    elif command == "log":
        if len(sys.argv) < 3:
            print("Usage: ta log <command>")
            return
        cmd = ' '.join(sys.argv[2:])
        assistant.log_command(cmd)
        print(f"✓ Logged command: {cmd}")
    
    elif command == "search":
        if len(sys.argv) < 3:
            print("Usage: ta search <query>")
            return
        query = ' '.join(sys.argv[2:])
        results = assistant.search_commands(query)
        print(f"\n📝 Found {len(results)} matching commands:\n")
        for cmd, wd, ts, exit_code in results:
            status = "✓" if exit_code == 0 else "✗"
            print(f"{status} {cmd}")
            print(f"   {wd} | {ts}\n")
    
    elif command == "history":
        results = assistant.get_recent_commands(20)
        print("\n📜 Recent commands:\n")
        for cmd, wd, ts, exit_code in results:
            status = "✓" if exit_code == 0 else "✗"
            print(f"{status} {cmd}")
            print(f"   {wd} | {ts}\n")
    
    elif command == "ssh":
        hosts = assistant.get_ssh_hosts()
        print("\n🔐 SSH Hosts (by usage):\n")
        for hostname, username, count, last_used in hosts:
            user_part = f"{username}@" if username else ""
            print(f"  {user_part}{hostname}")
            print(f"    Used {count} times | Last: {last_used}\n")
    
    elif command == "suggest":
        if len(sys.argv) < 3:
            print("Usage: ta suggest <partial_command>")
            return
        partial = ' '.join(sys.argv[2:])
        suggestions = assistant.suggest_command(partial)
        if suggestions:
            print("\n💡 Suggestions:\n")
            for i, cmd in enumerate(suggestions, 1):
                print(f"{i}. {cmd}")
        else:
            print("No suggestions found")


if __name__ == "__main__":
    main()
EOFPYTHON

chmod +x "$TA_DIR/ta.py"
echo "✓ Main script installed"

# Backup existing .zshrc
if [ -f "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✓ Backed up existing .zshrc"
fi

# Add integration to .zshrc if not already present
if ! grep -q "Terminal Assistant Shell Integration" "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" << 'EOFZSH'

# Terminal Assistant Shell Integration
# Terminal Assistant Shell Integration
export TA_PATH="$HOME/.terminal_assistant/ta.py"

# Load the hook system first
autoload -U add-zsh-hook

# NOW remove any existing hooks to prevent duplicates
add-zsh-hook -D preexec _ta_preexec_log
add-zsh-hook -D precmd _ta_precmd_log

# Capture command BEFORE it runs
function _ta_preexec_log() {
    _TA_LAST_CMD="$1"
}

# Log after completion (only once)
function _ta_precmd_log() {
    if [[ -n "$_TA_LAST_CMD" ]] && [[ ! "$_TA_LAST_CMD" =~ ^ta\ .* ]]; then
        (python3 "$TA_PATH" log "$_TA_LAST_CMD" >/dev/null 2>&1 &)
    fi
    unset _TA_LAST_CMD
}

# Add hooks
add-zsh-hook preexec _ta_preexec_log
add-zsh-hook precmd _ta_precmd_log

alias ta="python3 $TA_PATH"

function tai() {
    python3 "$TA_PATH" ask "$*"
}

function tah() {
    python3 "$TA_PATH" history
}

function tas() {
    python3 "$TA_PATH" search "$*"
}

echo "🤖 Terminal Assistant ready! Try 'tai <question>' for AI help"
EOFZSH
    
    echo "✓ Added integration to .zshrc"
else
    echo "⚠️  Integration already exists in .zshrc"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "📝 Next steps:"
echo "1. Restart your terminal or run: source ~/.zshrc"
echo "2. Try these commands:"
echo "   tai 'how do I list files recursively?'"
echo "   ta history"
echo "   ta ssh"
echo ""
echo "Your commands will be automatically logged from now on!"