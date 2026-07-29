import asyncio
import docker
from typing import List
from fastapi import WebSocket
from app.core.config import IGNORED_EVENTS

class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

    async def broadcast(self, message: dict):
        # Create a copy to iterate safely
        for connection in list(self.active_connections):
            try:
                await connection.send_json(message)
            except Exception:
                self.disconnect(connection)

manager = ConnectionManager()

def docker_event_listener(loop):
    """
    Background thread to listen for Docker events and broadcast them.
    """
    try:
        client = docker.from_env()
        # decode=True returns a generator of dicts
        events = client.events(decode=True)
        for event in events:
            # Filter out ignored events
            action = event.get("Action", "")
            if any(action.startswith(ignored) for ignored in IGNORED_EVENTS):
                continue
                
            # Broadcast event to all connected websockets
            # Since this runs in a thread, we need to schedule the coroutine in the main loop
            asyncio.run_coroutine_threadsafe(manager.broadcast(event), loop)
    except Exception as e:
        print(f"Error in docker event listener: {e}")
