#!/usr/bin/env python3
"""Wait for latest build to be VALID, set export compliance, create internal group 'Me',
add build + tester. Env: ASC_API_KEY_P8 (never printed), ASC_KEY_ID."""
import os, sys, time, json, urllib.request, urllib.error, jwt
KEY_ID = os.environ.get("ASC_KEY_ID", "2JLG54NH47"); ISSUER = "b816f285-1d7a-4f76-b6a9-c7cfa01d579a"
APP = os.environ.get("ASC_APP_ID", "6816757939"); USER_ID = "8168f71c-5643-42b9-beb4-cab71f8c1fa3"
WANT = os.environ.get("BUILD_NUMBER")  # optional
p8 = os.environ["ASC_API_KEY_P8"]
def tok():
    n = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": n, "exp": n + 1200, "aud": "appstoreconnect-v1"}, p8,
                      algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def api(m, path, body=None):
    r = urllib.request.Request("https://api.appstoreconnect.apple.com" + path, method=m,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": "Bearer " + tok(), "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(r) as x:
            t = x.read(); return x.status, (json.loads(t) if t else {})
    except urllib.error.HTTPError as e:
        t = e.read(); return e.code, (json.loads(t) if t else {})
build = None
for i in range(60):
    s, b = api("GET", f"/v1/builds?filter[app]={APP}&sort=-uploadedDate&limit=10")
    ds = [d for d in b.get("data", []) if not WANT or d["attributes"]["version"] == WANT]
    if ds:
        d = ds[0]; a = d["attributes"]
        print(time.strftime("%H:%M:%S"), "build", a["version"], a["processingState"], "usesNonExemptEncryption=", a.get("usesNonExemptEncryption"), flush=True)
        if a["processingState"] in ("VALID", "FAILED", "INVALID"): build = d; break
    else: print(time.strftime("%H:%M:%S"), "no build yet", s, flush=True)
    time.sleep(30)
if not build or build["attributes"]["processingState"] != "VALID": sys.exit("build not VALID")
bid = build["id"]
if build["attributes"].get("usesNonExemptEncryption") is None:
    print("set compliance:", api("PATCH", f"/v1/builds/{bid}", {"data": {"type": "builds", "id": bid, "attributes": {"usesNonExemptEncryption": False}}})[0])
s, b = api("GET", f"/v1/betaGroups?filter[app]={APP}&filter[name]=Me")
g = [x for x in b.get("data", []) if x["attributes"]["name"] == "Me"]
if g: gid = g[0]["id"]; print("group exists", gid)
else:
    s, b = api("POST", "/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {"name": "Me", "isInternalGroup": True},
        "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
    print("create group:", s, b.get("errors")); gid = b["data"]["id"]
s, b = api("POST", f"/v1/betaGroups/{gid}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
print("add build to group:", s, b.get("errors"))
# internal testers: add the ASC user to the group
s, b = api("POST", f"/v1/betaGroups/{gid}/relationships/betaTesters", {"data": [{"type": "betaTesters", "id": USER_ID}]})
print("add tester by user id:", s, b.get("errors"))
if s >= 300:
    s, b = api("POST", "/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {"email": "gmunoz512@icloud.com", "firstName": "German", "lastName": "Munoz"},
        "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})
    print("create betaTester:", s, b.get("errors"), b.get("data", {}).get("id"))
s, b = api("GET", f"/v1/betaGroups/{gid}/betaTesters")
for t in b.get("data", []): print("tester in group:", t["id"], t["attributes"].get("email"), t["attributes"].get("state"), t["attributes"].get("inviteType"))
s, b = api("GET", f"/v1/builds/{bid}/buildBetaDetail")
print("buildBetaDetail:", b.get("data", {}).get("attributes"))
