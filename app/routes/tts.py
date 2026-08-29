"""文本转语音 /api/tts（Edge TTS，免费无需 Key）。"""
import hashlib
import os
import tempfile
import threading

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field

from app.auth import get_current_user
from app.config import get_setting


def _resolve_proxy():
    """读系统设置里的代理，并把宿主机回环地址归一化为容器可见地址。"""
    raw = (get_setting("proxy_url", "") or "").strip()
    if not raw:
        return None
    if "127.0.0.1" in raw or "localhost" in raw:
        raw = raw.replace("127.0.0.1", "host.docker.internal").replace("localhost", "host.docker.internal")
    return raw

router = APIRouter(prefix="/api/tts", tags=["tts"])

# 常用中文音色（名称 -> edge 音色 id）
VOICES = {
    "xiaoxiao": {"id": "zh-CN-XiaoxiaoNeural", "label": "晓晓（温柔女声）"},
    "xiaoyi": {"id": "zh-CN-XiaoyiNeural", "label": "晓伊（活泼女声）"},
    "yunxi": {"id": "zh-CN-YunxiNeural", "label": "云希（阳光男声）"},
    "yunyang": {"id": "zh-CN-YunyangNeural", "label": "云扬（新闻男声）"},
    "yunjian": {"id": "zh-CN-YunjianNeural", "label": "云健（沉稳男声）"},
}

_cache_dir = os.path.join(tempfile.gettempdir(), "whateat-tts")
os.makedirs(_cache_dir, exist_ok=True)
_lock = threading.Lock()


class TtsRequest(BaseModel):
    text: str = Field(min_length=1, max_length=500)
    voice: str = "xiaoxiao"
    rate: float = Field(default=1.0, ge=0.5, le=2.0)   # 语速倍率，1.0 为正常
    pitch: float = Field(default=1.0, ge=0.5, le=2.0)  # 音调倍率，1.0 为正常


@router.get("/voices")
def list_voices(user=Depends(get_current_user)):
    return {"voices": [{"key": k, "label": v["label"]} for k, v in VOICES.items()]}


@router.post("")
async def synthesize(
    body: TtsRequest,
    user=Depends(get_current_user),
):
    text = (body.text or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="文本不能为空")
    voice = body.voice if body.voice in VOICES else "xiaoxiao"
    # 倍率转 edge-tts 字符串：1.0 -> "+0%"/"+0Hz"，1.2 -> "+20%"，0.9 -> "-10%"
    rate = f"{int(round((body.rate - 1) * 100)):+d}%"
    pitch = f"{int(round((body.pitch - 1) * 100)):+d}Hz"

    key = hashlib.sha1(f"{voice}|{rate}|{pitch}|{text}".encode("utf-8")).hexdigest()
    out = os.path.join(_cache_dir, key + ".mp3")
    with _lock:
        if not os.path.isfile(out) or os.path.getsize(out) == 0:
            import edge_tts
            try:
                proxy = _resolve_proxy()
                # FastAPI async 端点已在事件循环中，直接 await
                await edge_tts.Communicate(text, VOICES[voice]["id"], rate=rate, pitch=pitch, proxy=proxy).save(out)
            except Exception as e:
                raise HTTPException(status_code=502, detail=f"TTS 合成失败: {e}")
    return FileResponse(out, media_type="audio/mpeg", filename="speech.mp3")
