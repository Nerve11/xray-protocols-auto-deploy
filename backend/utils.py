"""Utility functions for Xray dashboard."""

from __future__ import annotations

import asyncio
import io
import logging
import subprocess
from typing import Optional
from uuid import uuid4

import qrcode

logger = logging.getLogger(__name__)


def generate_uuid() -> str:
    """Generate UUID for new profile."""
    return str(uuid4())


async def generate_qr_code(data: str) -> io.BytesIO:
    """Generate QR code PNG image.
    
    Args:
        data: String to encode (usually VLESS/VMess link).
    
    Returns:
        BytesIO buffer containing PNG image.
    """
    qr = qrcode.QRCode(
        version=1,
        error_correction=qrcode.constants.ERROR_CORRECT_L,
        box_size=10,
        border=4,
    )
    qr.add_data(data)
    qr.make(fit=True)
    
    img = qr.make_image(fill_color="black", back_color="white")
    
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    buffer.seek(0)
    
    return buffer


async def get_server_ip() -> str:
    """Get server public IPv4 address.
    
    Returns:
        Public IP address as string.
    """
    try:
        process = await asyncio.create_subprocess_exec(
            "curl",
            "-s4",
            "https://ifconfig.me",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode == 0 and stdout:
            return stdout.decode().strip()
        
        # Fallback methods
        for url in ["https://api.ipify.org", "https://ipinfo.io/ip"]:
            try:
                process = await asyncio.create_subprocess_exec(
                    "curl",
                    "-s4",
                    url,
                    stdout=asyncio.subprocess.PIPE,
                )
                stdout, _ = await process.communicate()
                if process.returncode == 0 and stdout:
                    return stdout.decode().strip()
            except Exception:
                continue
        
        logger.warning("Failed to detect public IP, using localhost")
        return "127.0.0.1"
    except Exception as e:
        logger.error(f"Error getting server IP: {e}")
        return "127.0.0.1"


async def restart_xray_service() -> bool:
    """Restart Xray systemd service.
    
    Returns:
        True if restart succeeded, False otherwise.
    """
    try:
        process = await asyncio.create_subprocess_exec(
            "systemctl",
            "restart",
            "xray",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        await process.communicate()
        
        if process.returncode == 0:
            logger.info("Xray service restarted successfully")
            return True
        else:
            logger.error("Failed to restart Xray service")
            return False
    except Exception as e:
        logger.error(f"Error restarting Xray: {e}")
        return False


async def check_xray_status() -> bool:
    """Check if Xray service is running.
    
    Returns:
        True if active, False otherwise.
    """
    try:
        process = await asyncio.create_subprocess_exec(
            "systemctl",
            "is-active",
            "--quiet",
            "xray",
        )
        await process.wait()
        return process.returncode == 0
    except Exception:
        return False


def validate_uuid(uuid_str: str) -> bool:
    """Validate UUID format.
    
    Args:
        uuid_str: UUID string to validate.
    
    Returns:
        True if valid UUID, False otherwise.
    """
    try:
        from uuid import UUID
        UUID(uuid_str)
        return True
    except (ValueError, AttributeError):
        return False