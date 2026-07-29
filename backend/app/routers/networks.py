from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Any
import docker
from app.core.security import get_api_key
from app.core.utils import get_docker_client

router = APIRouter(
    prefix="/networks", tags=["networks"], dependencies=[Depends(get_api_key)]
)


@router.get("", response_model=List[Dict[str, Any]])
async def list_networks():
    """
    Get a list of all Docker networks.
    """
    client = get_docker_client()
    try:
        networks = client.networks.list()
        result = []
        for net in networks:
            result.append(
                {
                    "id": net.id,
                    "name": net.name,
                    "driver": net.attrs.get("Driver"),
                    "scope": net.attrs.get("Scope"),
                    "ipam": net.attrs.get("IPAM"),
                    "containers": net.attrs.get("Containers"),
                    "short_id": net.short_id,
                    "created": net.attrs.get("Created"),
                }
            )
        return result
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving networks: {str(e)}"
        )
    finally:
        client.close()


@router.get("/{network_id}", response_model=Dict[str, Any])
async def get_network_details(network_id: str):
    """
    Get detailed information about a specific Docker network.
    """
    client = get_docker_client()
    try:
        network = client.networks.get(network_id)
        return network.attrs
    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail="Network not found")
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Error retrieving network details: {str(e)}"
        )
    finally:
        client.close()
