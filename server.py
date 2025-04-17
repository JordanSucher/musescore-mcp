from mcp.server.fastmcp import FastMCP
import websockets
import json
import sys
import logging
from typing import Dict, Any, Optional, List, Literal, TypedDict

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler(sys.stderr)]
)
logger = logging.getLogger("MuseScoreMCP")

class MuseScoreClient:
    """Client to communicate with MuseScore WebSocket API."""
    
    def __init__(self, host: str = "localhost", port: int = 8765):
        self.uri = f"ws://{host}:{port}"
        self.websocket = None
    
    async def connect(self):
        """Connect to the MuseScore WebSocket API."""
        try:
            self.websocket = await websockets.connect(self.uri)
            logger.info(f"Connected to MuseScore API at {self.uri}")
            return True
        except Exception as e:
            logger.error(f"Failed to connect to MuseScore API: {str(e)}")
            return False
    
    async def send_command(self, action: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """Send a command to MuseScore and wait for response."""
        if not self.websocket:
            connected = await self.connect()
            if not connected:
                return {"error": "Not connected to MuseScore"}
        
        if params is None:
            params = {}
        
        command = {"action": action, "params": params}
        
        try:
            logger.info(f"Sending command: {json.dumps(command)}")
            await self.websocket.send(json.dumps(command))
            response = await self.websocket.recv()
            logger.info(f"Received response: {response}")
            return json.loads(response)
        except Exception as e:
            logger.error(f"Error sending command: {str(e)}")
            return {"error": str(e)}
    
    async def close(self):
        """Close the WebSocket connection."""
        if self.websocket:
            await self.websocket.close()
            self.websocket = None
            logger.info("Disconnected from MuseScore API")


class MuseScoreMCP:
    """MCP server providing tools for LLMs to interact with MuseScore."""
    
    def __init__(self, app_name: str = "MuseScore Assistant"):
        self.mcp = FastMCP(app_name)
        self.client = MuseScoreClient()
        
        # Register all the tools based on the JS client functionality
        self.register_tools()
    
    def register_tools(self):
        """Register all tools that map to the JavaScript client functions."""
        
        # Connection & Utility Tools
        @self.mcp.tool()
        async def connect_to_musescore():
            """Connect to the MuseScore WebSocket API."""
            result = await self.client.connect()
            return {"success": result}
        
        @self.mcp.tool()
        async def ping_musescore():
            """Ping the MuseScore WebSocket API to check connection."""
            return await self.client.send_command("ping")
        
        # Score Management Tools
        @self.mcp.tool()
        async def get_score():
            """Get information about the current score."""
            return await self.client.send_command("getScore")
        
        # Cursor & Navigation Tools
        @self.mcp.tool()
        async def get_cursor_info():
            """Get information about the current cursor position."""
            return await self.client.send_command("getCursorInfo")
        
        # @self.mcp.tool()
        # async def go_to_measure(measure: int):
        #     """Navigate to a specific measure."""
        #     return await self.client.send_command("goToMeasure", {"measure": measure})
        
        # @self.mcp.tool()
        # async def go_to_final_measure():
        #     """Navigate to the final measure of the score."""
        #     return await self.client.send_command("goToFinalMeasure")
        
        # @self.mcp.tool()
        # async def go_to_beginning_of_score():
        #     """Navigate to the beginning of the score."""
        #     return await self.client.send_command("goToBeginningOfScore")
        
        # @self.mcp.tool()
        # async def next_element():
        #     """Move cursor to the next element."""
        #     return await self.client.send_command("nextElement")
        
        # @self.mcp.tool()
        # async def prev_element():
        #     """Move cursor to the previous element."""
        #     return await self.client.send_command("prevElement")
        
        # @self.mcp.tool()
        # async def select_current_measure():
        #     """Select the current measure."""
        #     return await self.client.send_command("selectCurrentMeasure")
        
        # # Notes & Measures Tools
        # @self.mcp.tool()
        # async def add_note(pitch: int = 64, duration: object = {"numerator": 1, "denominator": 4}):
        #     """Add a note at the current cursor position with the specified pitch and duration."""
        #     return await self.client.send_command("addNote", {"pitch": pitch, "duration": duration})
        
        # @self.mcp.tool()
        # async def add_rest(duration: object = {"numerator": 1, "denominator": 4}):
        #     """Add a rest at the current cursor position."""
        #     return await self.client.send_command("addRest", {"duration": duration})
        
        # @self.mcp.tool()
        # async def add_tuplet(duration: object = {"numerator": 1, "denominator": 4}, ratio: object = {"numerator": 3, "denominator": 2}):
        #     """Add a tuplet at the current cursor position."""
        #     return await self.client.send_command("addTuplet", {
        #         "ratio": {"duration": duration, "ratio": ratio}
        #     })
        
        # @self.mcp.tool()
        # async def insert_measure():
        #     """Insert a measure at the current position."""
        #     return await self.client.send_command("insertMeasure")
        
        # @self.mcp.tool()
        # async def append_measure(count: int = 1):
        #     """Append measures to the end of the score."""
        #     return await self.client.send_command("appendMeasure", {"count": count})
        
        # @self.mcp.tool()
        # async def delete_selection(measure: Optional[int] = None):
        #     """Delete the current selection or specified measure."""
        #     params = {}
        #     if measure is not None:
        #         params["measure"] = measure
        #     return await self.client.send_command("deleteSelection", params)
        
        # # Time & Tempo Tools
        # @self.mcp.tool()
        # async def set_time_signature(numerator: int = 4, denominator: int = 4):
        #     """Set the time signature."""
        #     return await self.client.send_command("setTimeSignature", {
        #         "numerator": numerator,
        #         "denominator": denominator
        #     })

        type ValidAction = Literal["getScore","addNote",
            "addRest","addTuplet","appendMeasure","deleteSelection","getCursorInfo","goToMeasure","nextElement","prevElement","selectCurrentMeasure","processSequence","insertMeasure","goToFinalMeasure","goToBeginningOfScore","setTimeSignature"]

        class getScoreAction(TypedDict):
            action: Literal["getScore"]
            params: Dict[str, Any]

        class addNoteParams(TypedDict):
            pitch: int
            duration: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool

        class addNoteAction(TypedDict):
            action: Literal["addNote"]
            params: addNoteParams

        class addRestParams(TypedDict):
            duration: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool

        class addRestAction(TypedDict):
            action: Literal["addRest"]
            params: addRestParams

        class addTupletParams(TypedDict):
            duration: Dict[Literal["numerator", "denominator"], int]
            ratio: Dict[Literal["numerator", "denominator"], int]
            advanceCursorAfterAction: bool

        class addTupletAction(TypedDict):
            action: Literal["addTuplet"]
            params: addTupletParams

        class appendMeasureAction(TypedDict):
            action: Literal["appendMeasure"]
            params: Dict[str, Any]

        class deleteSelectionAction(TypedDict):
            action: Literal["deleteSelection"]
            params: Dict[str, Any]

        class getCursorInfoAction(TypedDict):
            action: Literal["getCursorInfo"]
            params: Dict[str, Any]

        class goToMeasureParams(TypedDict):
            measure: int

        class goToMeasureAction(TypedDict):
            action: Literal["goToMeasure"]
            params: goToMeasureParams

        class nextElementAction(TypedDict):
            action: Literal["nextElement"]
            params: Dict[str, Any]

        class prevElementAction(TypedDict):
            action: Literal["prevElement"]
            params: Dict[str, Any]

        class selectCurrentMeasureAction(TypedDict):
            action: Literal["selectCurrentMeasure"]
            params: Dict[str, Any]

        class insertMeasureAction(TypedDict):
            action: Literal["insertMeasure"]
            params: Dict[str, Any]

        class goToFinalMeasureAction(TypedDict):
            action: Literal["goToFinalMeasure"]
            params: Dict[str, Any]

        class goToBeginningOfScoreAction(TypedDict):
            action: Literal["goToBeginningOfScore"]
            params: Dict[str, Any]

        class setTimeSignatureParams(TypedDict):
            numerator: int
            denominator: int

        class setTimeSignatureAction(TypedDict):
            action: Literal["setTimeSignature"]
            params: setTimeSignatureParams

        class undoAction(TypedDict):
            action: Literal["undo"]
            params: Dict[str, Any]

        
        type ActionSequence = List[getScoreAction | addNoteAction | addRestAction | addTupletAction | appendMeasureAction | deleteSelectionAction | getCursorInfoAction | goToMeasureAction | nextElementAction | prevElementAction | selectCurrentMeasureAction | insertMeasureAction | goToFinalMeasureAction | goToBeginningOfScoreAction | setTimeSignatureAction | undoAction]

        @self.mcp.tool()
        async def processSequence(sequence: ActionSequence):
            """Process a sequence of commands."""
            return await self.client.send_command("processSequence", {"sequence": sequence})
    
    def run(self):
        """Run the MCP server."""
        sys.stderr.write("MuseScore MCP Server starting up...\n")
        sys.stderr.flush()
        logger.info("MuseScore MCP Server is running")
        self.mcp.run()


# Main entry point
if __name__ == "__main__":
    # Create and run the server
    server = MuseScoreMCP("MuseScore Assistant")
    server.run()
