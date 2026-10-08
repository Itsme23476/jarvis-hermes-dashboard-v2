"""
Text to speech.

ElevenLabs when a key is present, browser speechSynthesis otherwise.

The key stays here, server-side. The browser asks /api/speak for audio and gets
mp3 bytes back — it never sees the key, so nothing leaks into devtools, the
page source, or a screen recording.
"""
import json
import os
import urllib.error
import urllib.request

# Rachel — calm, British-adjacent. Override with ELEVENLABS_VOICE_ID.
DEFAULT_VOICE = "21m00Tcm4TlvDq8ikWAM"


def model():
    return os.environ.get("ELEVENLABS_MODEL", "eleven_turbo_v2_5")


def available():
    return bool(os.environ.get("ELEVENLABS_API_KEY"))


def voice_id():
    return os.environ.get("ELEVENLABS_VOICE_ID", DEFAULT_VOICE)


def _reason(e):
    """ElevenLabs' machine-readable status from an HTTPError — never the key."""
    try:
        detail = json.loads(e.read(600)).get("detail", {})
        if isinstance(detail, dict):
            return str(detail.get("status") or detail.get("message") or f"http_{e.code}")[:80]
        return str(detail)[:80]
    except Exception:                                      # noqa: BLE001
        return f"http_{e.code}"


def verify():
    """Cheap check that ElevenLabs accepts the key. Returns (ok, detail).

    detail is the subscription tier when ok, otherwise ElevenLabs' status such as
    'invalid_api_key' or 'missing_permissions'. The key itself is never returned,
    so this is safe to show in the banner, /api/status and the HUD.
    """
    if not available():
        return False, "no_key"
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/user/subscription",
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"]},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return True, str(json.loads(r.read()).get("tier", "ok"))
    except urllib.error.HTTPError as e:
        return False, _reason(e)
    except Exception as e:                                 # noqa: BLE001
        return False, f"network: {str(e)[:60]}"


def speak(text):
    """Returns mp3 bytes, or raises. Caller decides what to do on failure."""
    if not available():
        raise RuntimeError("no ELEVENLABS_API_KEY")
    text = (text or "").strip()
    if not text:
        raise ValueError("empty text")

    req = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id()}",
        data=json.dumps({
            "text": text[:2500],
            "model_id": model(),
            "voice_settings": {
                "stability": 0.42,          # a little variation; 0.5+ goes flat
                "similarity_boost": 0.85,
                "style": 0.25,
                "use_speaker_boost": True,
            },
        }).encode(),
        method="POST",
        headers={
            "content-type": "application/json",
            "accept": "audio/mpeg",
            "xi-api-key": os.environ["ELEVENLABS_API_KEY"],
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read()
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"ElevenLabs TTS HTTP {e.code}: {_reason(e)}") from e


def transcribe(audio, mime="audio/webm"):
    """Speech to text via ElevenLabs Scribe. Returns the transcript, or raises.

    Used instead of the browser's Web Speech API because that one only exists in
    Chrome and is a silently-failing stub in Brave — and because it ships your
    audio to Google. This keeps listening on the same provider as speaking.
    """
    if not available():
        raise RuntimeError("no ELEVENLABS_API_KEY")
    if not audio:
        raise ValueError("empty audio")

    ext = {"audio/webm": "webm", "audio/ogg": "ogg", "audio/mp4": "mp4",
           "audio/mpeg": "mp3", "audio/wav": "wav"}.get(mime.split(";")[0], "webm")
    boundary = "----jarvis" + os.urandom(8).hex()
    b = boundary.encode()

    body = b"".join([
        b"--", b, b"\r\n",
        b'Content-Disposition: form-data; name="model_id"\r\n\r\nscribe_v1\r\n',
        b"--", b, b"\r\n",
        f'Content-Disposition: form-data; name="file"; filename="turn.{ext}"\r\n'.encode(),
        f"Content-Type: {mime}\r\n\r\n".encode(),
        audio, b"\r\n",
        b"--", b, b"--\r\n",
    ])

    req = urllib.request.Request(
        "https://api.elevenlabs.io/v1/speech-to-text",
        data=body, method="POST",
        headers={
            "content-type": f"multipart/form-data; boundary={boundary}",
            "xi-api-key": os.environ["ELEVENLABS_API_KEY"],
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return (json.loads(r.read()).get("text") or "").strip()
    except urllib.error.HTTPError as e:
        # Surface auth/quota problems to the HUD by status code, never the key.
        raise RuntimeError(f"ElevenLabs STT HTTP {e.code}: {_reason(e)}") from e


def voices():
    """List the account's voices, so you can find an id to put in .env."""
    if not available():
        return []
    req = urllib.request.Request(
        "https://api.elevenlabs.io/v2/voices",
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"]},
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            body = json.loads(r.read())
    except Exception:                                  # noqa: BLE001
        return []
    return [dict(id=v.get("voice_id"), name=v.get("name"),
                 labels=v.get("labels", {}))
            for v in body.get("voices", [])]
