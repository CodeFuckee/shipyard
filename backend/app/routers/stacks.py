from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Any
from app.core.security import get_api_key
from app.core.utils import get_docker_client, process_container_summary, get_current_container_id

router = APIRouter(
    prefix="/stacks",
    tags=["stacks"],
    dependencies=[Depends(get_api_key)]
)

@router.get("/{stack_name}/containers", response_model=List[Dict[str, Any]])
async def get_stack_containers(stack_name: str):
    """
    Get all containers belonging to a specific stack (Docker Compose project).
    """
    client = get_docker_client()
    self_id = get_current_container_id()
    try:
        # Filter by label: com.docker.compose.project
        # Also support Swarm stacks: com.docker.stack.namespace
        
        # Since client.containers.list filters logic is AND, we can't do OR easily in one query if we want to support both.
        # But standard docker-compose uses com.docker.compose.project.
        # Let's stick to com.docker.compose.project for now as per utils.py logic.
        
        filters = {"label": f"com.docker.compose.project={stack_name}"}
        containers = client.containers.list(all=True, filters=filters)
        
        # If no containers found, maybe check for swarm stack label?
        if not containers:
             filters_swarm = {"label": f"com.docker.stack.namespace={stack_name}"}
             containers_swarm = client.containers.list(all=True, filters=filters_swarm)
             containers.extend(containers_swarm)

        result = [process_container_summary(c, self_id) for c in containers]
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error retrieving stack containers: {str(e)}")
    finally:
        client.close()
