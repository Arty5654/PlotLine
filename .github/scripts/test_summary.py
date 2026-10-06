#!/usr/bin/env python3
"""
Turns test results into small JSON summaries and the PR comment.

  test_summary.py backend <surefire-reports-dir> <out.json>
  test_summary.py ios <tests.xcresult> <out.json>
  test_summary.py comment <backend.json> <ios.json> <commit-sha> <out.md>

A missing or unreadable result (e.g. the build failed) becomes {"ran": false}.
"""
import glob
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

# Which app area each test class / suite belongs to, in the order the comment lists them.
AREAS = [
    "Sign in, accounts & security", "Calendar", "Budget & spending", "Investing",
    "Nutrition", "Friends", "Profile", "Goals", "Grocery lists", "App startup",
]

BACKEND_AREAS = {
    "CalendarFeatureTest": "Calendar",
    "BudgetSpendingFeatureTest": "Budget & spending",
    "InvestingFeatureTest": "Investing",
    "NutritionFeatureTest": "Nutrition",
    "FriendsFeatureTest": "Friends",
    "ProfileFeatureTest": "Profile",
    "GoalsFeatureTest": "Goals",
    "GroceryListServiceTest": "Grocery lists",
    "GroceryListControllerTest": "Grocery lists",
    "BackendApplicationTests": "App startup",
}

IOS_AREAS = {
    "AuthTests": "Sign in, accounts & security",
    "CalendarTests": "Calendar",
    "BudgetSpendingTests": "Budget & spending",
    "InvestingTests": "Investing",
    "NutritionTests": "Nutrition",
    "FriendsTests": "Friends",
    "ProfileTests": "Profile",
    "GoalsTests": "Goals",
    "GroceryTests": "Grocery lists",
}

MARKER = "<!-- plotline-test-results -->"


def empty_summary():
    return {"ran": True, "areas": {}, "failures": [], "skipped": []}


def add(summary, area, status, name, detail=""):
    counts = summary["areas"].setdefault(area, {"passed": 0, "failed": 0, "skipped": 0})
    counts[status] += 1
    if status == "failed":
        summary["failures"].append({"area": area, "name": name, "detail": detail[:300]})
    elif status == "skipped":
        summary["skipped"].append({"area": area, "name": name, "detail": detail[:200]})


def backend(reports_dir, out):
    files = glob.glob(os.path.join(reports_dir, "TEST-*.xml"))
    if not files:
        return write(out, {"ran": False})
    summary = empty_summary()
    for path in files:
        for case in ET.parse(path).getroot().iter("testcase"):
            cls = case.get("classname", "").split(".")[-1].split("$")[0]
            area = BACKEND_AREAS.get(cls, "Sign in, accounts & security")
            name = f"{cls}.{case.get('name', '?')}"
            failure = case.find("failure")
            if failure is None:
                failure = case.find("error")
            skipped = case.find("skipped")
            if failure is not None:
                add(summary, area, "failed", name, failure.get("message") or "")
            elif skipped is not None:
                add(summary, area, "skipped", name, skipped.get("message") or "")
            else:
                add(summary, area, "passed", name)
    write(out, summary)


def ios(xcresult, out):
    try:
        raw = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", xcresult],
                             capture_output=True, text=True, check=True).stdout
        data = json.loads(raw)
    except Exception:
        return write(out, {"ran": False})
    summary = empty_summary()

    def walk(node, suite):
        kind = node.get("nodeType")
        if kind == "Test Suite":
            suite = node.get("name", suite)
        if kind == "Test Case":
            area = IOS_AREAS.get(suite, "Other")
            result = (node.get("result") or "").lower()
            messages = [c.get("name", "") for c in node.get("children", []) if c.get("nodeType") == "Failure Message"]
            status = "failed" if result == "failed" else "skipped" if result == "skipped" else "passed"
            add(summary, area, status, f"{suite}: {node.get('name', '?')}", " / ".join(messages))
            return
        for child in node.get("children", []):
            walk(child, suite)

    for node in data.get("testNodes", []):
        walk(node, "")
    if not summary["areas"]:
        summary["ran"] = False
    write(out, summary)


def write(out, summary):
    with open(out, "w") as f:
        json.dump(summary, f, indent=2)


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {"ran": False}


def cell(summary, area):
    if not summary.get("ran"):
        return "—"
    counts = summary["areas"].get(area)
    if not counts:
        return "—"
    if counts["failed"]:
        return f"❌ {counts['failed']} failed / {counts['passed'] + counts['failed']}"
    text = f"✅ {counts['passed']}"
    if counts["skipped"]:
        text += f" (+{counts['skipped']} known bug)"
    return text


def totals(summary):
    p = f = s = 0
    for counts in summary.get("areas", {}).values():
        p += counts["passed"]; f += counts["failed"]; s += counts["skipped"]
    return p, f, s


def status_line(label, summary):
    if not summary.get("ran"):
        return f"⚠️ **{label}:** didn't run (build or setup failed, check the job log)"
    p, f, s = totals(summary)
    icon = "❌" if f else "✅"
    extra = f", {s} skipped (known bugs, see BUGS.md)" if s else ""
    return f"{icon} **{label}:** {p} passed, {f} failed{extra}"


def comment(backend_json, ios_json, sha, out):
    b, i = load(backend_json), load(ios_json)
    lines = [MARKER, f"## 🧪 Test results for `{sha[:7]}`", "",
             status_line("Backend", b), status_line("iOS", i), "",
             "| Area | Backend | iOS |", "|---|---|---|"]
    for area in AREAS:
        lines.append(f"| {area} | {cell(b, area)} | {cell(i, area)} |")

    failures = b.get("failures", []) + i.get("failures", [])
    if failures:
        lines += ["", "### ❌ Failing tests", ""]
        for item in failures[:40]:
            detail = item["detail"].replace("\n", " ").strip()
            lines.append(f"- **{item['area']}**: `{item['name']}`" + (f": {detail}" if detail else ""))

    skipped = b.get("skipped", []) + i.get("skipped", [])
    if skipped:
        lines += ["", "<details><summary>Skipped tests (known bugs)</summary>", ""]
        for item in skipped:
            lines.append(f"- `{item['name']}`: {item['detail']}")
        lines += ["", "</details>"]

    lines += ["", "_This comment updates on every push to this PR._"]
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    {"backend": backend, "ios": ios, "comment": comment}[cmd](*args)
