"""Materialize an existing upload key only on the ephemeral release runner."""
import base64
import os
from pathlib import Path
import re
import subprocess


def property_value(value):
    # java.util.Properties uses ISO-8859-1 and backslash escapes.
    result = ""
    for char in value:
        if char in "\\ =:#!":
            result += "\\" + char
        elif char in "\n\r\t\f":
            result += {"\n": "\\n", "\r": "\\r", "\t": "\\t", "\f": "\\f"}[char]
        elif ord(char) > 127:
            for index in range(0, len(char.encode("utf-16-be")), 2):
                result += "\\u" + char.encode("utf-16-be")[index:index + 2].hex()
        else:
            result += char
    return result


def main():
    names = ["ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD", "ANDROID_KEY_PASSWORD", "ANDROID_KEY_ALIAS", "PLAY_UPLOAD_CERTIFICATE_SHA256"]
    if any(not os.environ.get(name) for name in names):
        raise ValueError("Missing upload-signing secret or certificate fingerprint; see docs/google-play-release.md")
    os.umask(0o077)
    key = Path(os.environ["RUNNER_TEMP"]) / "legorganizer-upload.jks"
    key.write_bytes(base64.b64decode(os.environ["ANDROID_KEYSTORE_BASE64"], validate=True))
    result = subprocess.run(["keytool", "-J-Duser.language=en", "-list", "-v", "-keystore", str(key),
                             "-alias", os.environ["ANDROID_KEY_ALIAS"], "-storepass:env", "ANDROID_KEYSTORE_PASSWORD"],
                            capture_output=True, text=True, check=False)
    expected = os.environ["PLAY_UPLOAD_CERTIFICATE_SHA256"].replace(":", "").lower()
    match = re.search(r"SHA256:\s*([A-Fa-f0-9:]+)", result.stdout)
    if result.returncode or "PrivateKeyEntry" not in result.stdout or not re.fullmatch(r"[a-f0-9]{64}", expected) or not match or match[1].replace(":", "").lower() != expected:
        raise ValueError("Upload key could not be verified against the Play upload certificate fingerprint")
    values = {"storeFile": str(key), "storePassword": os.environ["ANDROID_KEYSTORE_PASSWORD"],
              "keyAlias": os.environ["ANDROID_KEY_ALIAS"], "keyPassword": os.environ["ANDROID_KEY_PASSWORD"]}
    Path("android/key.properties").write_text("".join(f"{key}={property_value(value)}\n" for key, value in values.items()), encoding="ascii")
    print("Existing upload key verified and prepared")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError) as error:
        raise SystemExit(f"Signing setup stopped: {error}") from None
