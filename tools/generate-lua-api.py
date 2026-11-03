#!/usr/bin/env python3
"""Dump the Lua API the C++ engine registers, as a Lua table, for the offline script tests.

The spell tests (tests/lua) run the real data/ scripts against a mock engine. The mock is built
from this dump, so a script calling a method or constant the engine does not register fails the
test just like it fails in game ("attempt to call a nil value (method ...)").

Usage:  python3 tools/generate-lua-api.py > api.lua
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "src"


def read_sources(pattern: str) -> str:
    return "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in sorted(SRC.glob(pattern)))


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def parse_enum_values(headers: str) -> dict[str, int]:
    """Best effort values for C++ enums/constants: NAME and Scope::NAME -> int."""
    values: dict[str, int] = {}

    def evaluate(expr: str):
        expr = expr.strip()
        expr = re.sub(r"\b(static_cast|std::underlying_type_t)<[^>]*>", "", expr)
        expr = re.sub(r"(?<=\d)[uUlL]+\b", "", expr)
        expr = expr.replace("::", "__")
        names = {k.replace("::", "__"): v for k, v in values.items()}
        if not re.fullmatch(r"[\w\s()+\-*/|&<>~^xXa-fA-F]*", expr):
            return None
        try:
            result = eval(expr, {"__builtins__": {}}, names)  # noqa: S307 - our own headers
        except Exception:
            return None
        return int(result) if isinstance(result, (int, bool)) else None

    for match in re.finditer(r"\benum\s+(class\s+|struct\s+)?(\w*)\s*(:\s*[\w:]+\s*)?\{(.*?)\}", headers, re.S):
        scope = match.group(2)
        current = -1
        for entry in match.group(4).split(","):
            entry = entry.strip()
            if not entry:
                continue
            name, _, expr = entry.partition("=")
            name = name.strip()
            if not re.fullmatch(r"[A-Za-z_]\w*", name):
                continue
            value = evaluate(expr) if expr else current + 1
            if value is None:
                value = current + 1
            current = value
            values.setdefault(name, value)
            if scope:
                values[f"{scope}::{name}"] = value

    for match in re.finditer(r"\b(?:static\s+)?(?:inline\s+)?constexpr\s+[\w:<>]+\s+(\w+)\s*=\s*([^;{]+);", headers):
        value = evaluate(match.group(2))
        if value is not None:
            values.setdefault(match.group(1), value)
    for match in re.finditer(r"^#define\s+(\w+)\s+([^\n]+)$", headers, re.M):
        value = evaluate(match.group(2))
        if value is not None:
            values.setdefault(match.group(1), value)
    return values


def lua_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    source = strip_comments(read_sources("*.cpp"))
    values = parse_enum_values(strip_comments(read_sources("*.h") + "\n" + source))
    fallback = iter(range(1_000_000, 10_000_000))

    def value_of(expr: str) -> int:
        expr = expr.strip()
        cast = re.fullmatch(r"static_cast<[^>]*>\((.*)\)", expr)
        if cast:
            expr = cast.group(1).strip()
        if re.fullmatch(r"-?\d+", expr):
            return int(expr)
        if expr in values:
            return values[expr]
        last = expr.split("::")[-1]
        return values.get(last, next(fallback))

    classes: dict[str, str] = {}
    for match in re.finditer(r'\bregisterClass\(\s*"(\w+)"\s*,\s*"(\w*)"', source):
        classes[match.group(1)] = match.group(2)
    tables = set(re.findall(r'\bregisterTable\(\s*"(\w+)"', source))

    methods: dict[str, set[str]] = {}
    for match in re.finditer(r'\bregister(?:Meta)?Method\(\s*"(\w+)"\s*,\s*"(\w+)"', source):
        methods.setdefault(match.group(1), set()).add(match.group(2))
    # luaL_register(L, "configManager", LuaScriptInterface::luaConfigManagerTable) + its luaL_Reg array.
    for match in re.finditer(r'\bluaL_register\(\s*\w+\s*,\s*"(\w+)"\s*,\s*[\w:]*?(\w+)\s*\)', source):
        array = re.search(r"luaL_Reg\s+[\w:]*?" + match.group(2) + r"\[\]\s*=\s*\{(.*?)\};", source, re.S)
        if array:
            tables.add(match.group(1))
            methods.setdefault(match.group(1), set()).update(re.findall(r'\{\s*"(\w+)"', array.group(1)))
    tables |= set(methods) - set(classes)

    functions = set(re.findall(r'\bregisterGlobalMethod\(\s*"(\w+)"', source))
    functions |= set(re.findall(r'\blua_register\(\s*[\w>.-]+\s*,\s*"(\w+)"', source))

    globals_: dict[str, int] = {}
    for match in re.finditer(r"\bregisterEnum\(\s*([A-Za-z_][\w:]*)\s*\)", source):
        globals_[match.group(1).split("::")[-1]] = value_of(match.group(1))
    for match in re.finditer(r'\bregisterGlobalVariable\(\s*"(\w+)"\s*,\s*([^;]+?)\);', source):
        globals_[match.group(1)] = value_of(match.group(2))
    # for (const char* name : {"A", "B", ...}) { registerGlobalVariable(name, 0); }
    for match in re.finditer(r"for\s*\(\s*const\s+char\s*\*\s*(\w+)\s*:\s*\{(.*?)\}\s*\)\s*\{\s*registerGlobalVariable\(\s*\1\s*,\s*([^;]+?)\);", source, re.S):
        for name in re.findall(r'"(\w+)"', match.group(2)):
            globals_[name] = value_of(match.group(3))
    booleans = {m.group(1): m.group(2) == "true" for m in re.finditer(r'\bregisterGlobalBoolean\(\s*"(\w+)"\s*,\s*(\w+)', source)}

    fields: dict[str, dict[str, int]] = {}
    for match in re.finditer(r'\bregisterEnumIn\(\s*"(\w+)"\s*,\s*([\w:]+)\s*\)', source):
        fields.setdefault(match.group(1), {})[match.group(2).split("::")[-1]] = value_of(match.group(2))
    for match in re.finditer(r"\bregisterEnumClass\(\s*([\w:]+)\s*\)", source):
        scope, _, name = match.group(1).rpartition("::")
        if not scope:
            continue
        fields.setdefault(scope.split("::")[-1], {})[name] = value_of(match.group(1))
    for match in re.finditer(r'\bregisterVariable\(\s*"(\w+)"\s*,\s*"(\w+)"\s*,\s*([^;]+?)\);', source):
        fields.setdefault(match.group(1), {})[match.group(2)] = value_of(match.group(3))

    out = ["-- Generated by tools/generate-lua-api.py from src/. Do not edit.", "return {"]
    out.append("\tclasses = {")
    for name in sorted(classes):
        names = ", ".join(lua_string(m) for m in sorted(methods.get(name, ())))
        out.append(f"\t\t{name} = {{ base = {lua_string(classes[name])}, methods = {{ {names} }} }},")
    out.append("\t},")
    out.append("\ttables = {")
    for name in sorted(tables | set(fields)):
        names = ", ".join(lua_string(m) for m in sorted(methods.get(name, ())))
        entries = ", ".join(f"{k} = {v}" for k, v in sorted(fields.get(name, {}).items()))
        out.append(f"\t\t{name} = {{ functions = {{ {names} }}, fields = {{ {entries} }} }},")
    out.append("\t},")
    out.append("\tfunctions = { " + ", ".join(lua_string(f) for f in sorted(functions)) + " },")
    out.append("\tglobals = {")
    for name in sorted(globals_):
        out.append(f"\t\t{name} = {globals_[name]},")
    for name in sorted(booleans):
        out.append(f"\t\t{name} = {'true' if booleans[name] else 'false'},")
    out.append("\t},")
    out.append("}")
    sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
