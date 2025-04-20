# MuseScore MCP Server

This MCP (Model Context Protocol) server integrates MuseScore with LLM clients like Claude Desktop, enabling music composition and analysis through natural language.

## Features

The server allows an MCP-connected LLM to:

- Connect to MuseScore and manipulate an open score
- Add notes and rests
- Select and delete
- Create tuplets
- Undo a change

## Limitations

- Can not understand multiple staffs or navigate between them

## Requirements

- Python 3.9+
- MuseScore 3 or 4 installed
- MCP Python SDK

## Installation

1. Clone this repository:
   ```
   git clone https://github.com/yourusername/musescore-mcp-server.git
   cd musescore-mcp-server
   ```

2. Install dependencies, either in a venv or globally:
   ```
   pip install -r requirements.txt
   ```

3. Install the musescore-mcp-plugin by copying it into your MuseScore plugins dir (on my mac this was ~/Documents/MuseScore4/plugins)

4. Configure your LLM with the MCP server (server.py). If you are using Claude Desktop and a venv, this can be done by creating a claude_desktop_config file like so:
   ```json
   {
    "mcpServers": {
      "musescore": {
        "command": "bash",
        "args": [
          "-c",
          "source /path/to/venv/activate && python3 /path/to/server.py"
        ]
      }
    }
   ```
   
## Usage

### Prepare MuseScore

Open musescore and whatever score you want to use. Then, connect the musescore-mcp-plugin and launch it by selecting it from the plugins menu.

### Example Queries

Once connected, you can ask Claude questions like:

- "Help me come up with some possible chords for the melody in my score
- Compose a simple melody and show me 4 ways to harmonize it
- Extend the melody in measures 1-12 with 4 measures that match the style of this piece

## Development

If you want to add features to the MuseScore plugin and test them, the testClient.html file in this repo may be a useful development tool - simply extend it to call whatever functions you add. 
