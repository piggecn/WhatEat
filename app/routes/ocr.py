"""菜谱照片 OCR 识别 /api/ocr。"""
import io
import threading

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File

from app.auth import get_current_user

router = APIRouter(prefix="/api/ocr", tags=["ocr"])

_engine = None
_lock = threading.Lock()

ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/bmp"}
MAX_SIZE = 10 * 1024 * 1024  # 10MB


def _get_engine():
    global _engine
    if _engine is None:
        with _lock:
            if _engine is None:
                from rapidocr_onnxruntime import RapidOCR
                _engine = RapidOCR()
    return _engine


@router.post("")
async def ocr_image(
    file: UploadFile = File(...),
    user=Depends(get_current_user),
):
    """上传菜谱照片，返回识别文本（逐行）。"""
    if (file.content_type or "") not in ALLOWED_IMAGE_TYPES:
        raise HTTPException(status_code=400, detail="仅支持 jpg/png/webp/bmp 图片")
    data = await file.read()
    if len(data) > MAX_SIZE:
        raise HTTPException(status_code=400, detail="图片不能超过 10MB")
    try:
        engine = _get_engine()
        with _lock:
            result, _ = engine(data)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"识别失败: {e}")
    lines = [item[1] for item in (result or []) if item and len(item) > 1 and item[1]]
    return {"text": "\\n".join(lines), "lines": len(lines)}
