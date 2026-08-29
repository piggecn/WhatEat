"""图片上传路由 /api/upload。"""
import os
import uuid

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status

from app.auth import get_current_user, UPLOAD_DIR

router = APIRouter(prefix="/api/upload", tags=["upload"])

ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/png", "image/webp"}
ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".webp"}
MAX_SIZE = 5 * 1024 * 1024  # 5MB


@router.post("", response_model=None)
async def upload_image(
    file: UploadFile = File(...),
    user=Depends(get_current_user),
):
    if file.content_type not in ALLOWED_CONTENT_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="仅支持 jpg/png/webp 格式图片",
        )
    data = await file.read()
    if len(data) > MAX_SIZE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="图片大小不能超过 5MB",
        )

    os.makedirs(UPLOAD_DIR, exist_ok=True)
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in ALLOWED_EXT:
        ext = ".jpg"
    stem = uuid.uuid4().hex
    filename = f"{stem}{ext}"
    path = os.path.join(UPLOAD_DIR, filename)
    with open(path, "wb") as f:
        f.write(data)

    # 生成缩略图（列表页使用，减少流量）；PIL 不可用时静默跳过
    thumb_path = None
    try:
        from PIL import Image, ImageOps
        img = Image.open(path)
        img = ImageOps.exif_transpose(img)
        img.thumbnail((480, 480))
        tname = f"{stem}_t.webp"
        img.convert("RGB").save(os.path.join(UPLOAD_DIR, tname), "WEBP", quality=82)
        thumb_path = f"/uploads/{tname}"
    except Exception:
        pass

    return {"path": f"/uploads/{filename}", "thumb_path": thumb_path}
