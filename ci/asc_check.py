#!/usr/bin/env python3
"""ASC API helper: ensure bundle ID exists, check app record, list builds/users.
Reads the .p8 contents from env ASC_API_KEY_P8 (never printed)."""
import os, sys, time, json, urllib.request, urllib.error, jwt
KEY_ID, ISSUER = os.environ.get("ASC_KEY_ID","2JLG54NH47"), "b816f285-1d7a-4f76-b6a9-c7cfa01d579a"
BUNDLE = "com.gmunoz.soundphototest"
p8 = os.environ.get("ASC_API_KEY_P8")
if not p8: sys.exit("ASC_API_KEY_P8 not set")
now = int(time.time())
tok = jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
                 p8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def api(method, path, body=None):
    req = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.load(r)
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"{}")
s, b = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}")
ids = [d for d in b.get("data", []) if d["attributes"]["identifier"] == BUNDLE]
if ids: print("bundleId exists:", ids[0]["id"])
else:
    s, b = api("POST", "/v1/bundleIds", {"data": {"type": "bundleIds", "attributes":
        {"identifier": BUNDLE, "name": "SoundPhotoTest", "platform": "IOS"}}})
    print("register bundleId:", s, b.get("data", {}).get("id") or b.get("errors"))
s, b = api("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")
apps = b.get("data", [])
print("app record:", apps[0]["id"] if apps else f"MISSING (status {s})")
if apps:
    s, b = api("GET", f"/v1/builds?filter[app]={apps[0]['id']}&sort=-uploadedDate&limit=5")
    for d in b.get("data", []):
        a = d["attributes"]; print("build", a["version"], a["processingState"], a["uploadedDate"])
s, b = api("GET", "/v1/users?limit=50")
for u in b.get("data", []):
    a = u["attributes"]; print("user", u["id"], a.get("username"), a.get("roles"))
