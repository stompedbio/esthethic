// skeed server: global chat + cloud configs. No dependencies: node server.js
//
// Public endpoints
//   GET  /                          health check
//   GET  /info                      { name, version, motd, online, messages }
//   GET  /messages?after=<id>&name=<nick>
//                                   { last, online, motd, messages: [{ id, name, text, t }] }
//   POST /send         { name, text }
//   POST /config/save  { name, code }   -> { id }
//   GET  /config/<id>                   -> { code, by, t }
//
// Admin endpoint (only active when the ADMIN_KEY environment variable is set)
//   POST /admin  { key, action, name?, minutes?, text? }
//   actions: mute, unmute, ban, unban, clear, motd, announce
//
// Everything is kept in memory, so a restart clears chat, configs and bans.

const http = require("http");
const crypto = require("crypto");

const VERSION = "1.1.0";
const PORT = Number(process.env.PORT) || 3000;
const ADMIN_KEY = process.env.ADMIN_KEY || "";

const MAX_MESSAGES = 200;
const HISTORY_ON_JOIN = 20;
const MAX_TEXT = 120;
const PER_NAME_MIN_GAP_MS = 1500;
const PER_NAME_PER_MINUTE = 20;
const GLOBAL_PER_MINUTE = 300;
const ONLINE_WINDOW_MS = 30000;

const MAX_CONFIGS = 500;
const MAX_CODE_LENGTH = 6000;
const CONFIGS_PER_NAME_PER_MINUTE = 5;
const ADMIN_TRIES_PER_MINUTE = 10;

// ---------------------------------------------------------------
// Profanity filter (same rules as the Lua script)
// ---------------------------------------------------------------
const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s", "!": "i" };
const SUBSTRING_WORDS = ["fuck", "shit", "bitch", "cunt", "asshole", "putain", "connard", "salope", "encule"];
const WHOLE_WORDS = ["dick", "pussy", "bastard", "whore", "slut", "nique", "merde", "retard", "fag", "faggot", "nigga", "nigger", "fck", "fvck", "fuk", "sht", "btch"];
const ALLOWED_WORDS = ["scunthorpe"];

const collapse = (s) => s.replace(/(.)\1+/g, "$1");
const lettersOnly = (s) =>
  s.toLowerCase().replace(/[013457@$!]/g, (c) => LEET[c]).replace(/[^a-z]/g, "");

const SUB_C = SUBSTRING_WORDS.map(collapse);
const WHOLE_SET = new Set(WHOLE_WORDS.map(collapse));
const ALLOW_SET = new Set(ALLOWED_WORDS.map(collapse));

function isBad(norm) {
  if (!norm) return false;
  const c = collapse(norm);
  if (ALLOW_SET.has(c)) return false;
  for (const w of SUB_C) if (c.includes(w)) return true;
  return WHOLE_SET.has(c) || WHOLE_SET.has(c.replace(/s$/, ""));
}

function isFlagged(text) {
  const tokens = text.split(/\s+/).filter(Boolean);
  for (const tk of tokens) if (isBad(lettersOnly(tk))) return true;
  let i = 0;
  while (i < tokens.length) {
    if (tokens[i].length === 1) {
      let j = i, buf = "";
      while (j < tokens.length && tokens[j].length === 1) {
        buf += lettersOnly(tokens[j]);
        j++;
      }
      if (j - i >= 3 && isBad(buf)) return true;
      i = j;
    } else i++;
  }
  return false;
}

// ---------------------------------------------------------------
// State
// ---------------------------------------------------------------
const messages = [];
let nextId = 1;
let motd = "";

const banned = new Set();            // lowercase names
const muted = new Map();             // lowercase name -> expiry (ms)
const lastSeen = new Map();          // lowercase name -> last poll (ms)
const nameStamps = new Map();        // lowercase name -> [timestamps] for chat
const configStamps = new Map();      // lowercase name -> [timestamps] for config uploads
const configs = new Map();           // id -> { code, by, t }
let globalStamps = [];
let adminStamps = [];

const NAME_RE = /^[A-Za-z0-9_ .\-]{2,24}$/;
const CODE_RE = /^SKEED[A-Za-z0-9+/=]+$/;
const RESERVED_NAMES = new Set(["server", "admin", "system", "skeed", "owner", "mod", "moderator"]);
const ID_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";

function pushMessage(name, text) {
  const msg = { id: nextId++, name, text, t: Math.floor(Date.now() / 1000) };
  messages.push(msg);
  while (messages.length > MAX_MESSAGES) messages.shift();
  return msg;
}

function recent(stamps, now, windowMs) {
  return stamps.filter((t) => now - t < windowMs);
}

function allowedToChat(key, now) {
  globalStamps = recent(globalStamps, now, 60000);
  if (globalStamps.length >= GLOBAL_PER_MINUTE) return false;

  const stamps = recent(nameStamps.get(key) || [], now, 60000);
  if (stamps.length >= PER_NAME_PER_MINUTE) return false;
  if (stamps.length && now - stamps[stamps.length - 1] < PER_NAME_MIN_GAP_MS) return false;

  stamps.push(now);
  nameStamps.set(key, stamps);
  globalStamps.push(now);
  return true;
}

function allowedToUpload(key, now) {
  const stamps = recent(configStamps.get(key) || [], now, 60000);
  if (stamps.length >= CONFIGS_PER_NAME_PER_MINUTE) return false;
  stamps.push(now);
  configStamps.set(key, stamps);
  return true;
}

function onlineCount(now) {
  let n = 0;
  for (const t of lastSeen.values()) if (now - t < ONLINE_WINDOW_MS) n++;
  return n;
}

function newConfigId() {
  for (let tries = 0; tries < 20; tries++) {
    let id = "";
    const bytes = crypto.randomBytes(6);
    for (const b of bytes) id += ID_ALPHABET[b % ID_ALPHABET.length];
    if (!configs.has(id)) return id;
  }
  return null;
}

// remove stale bookkeeping once a minute
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of lastSeen) if (now - v > 10 * 60000) lastSeen.delete(k);
  for (const [k, v] of nameStamps) if (!v.some((t) => now - t < 60000)) nameStamps.delete(k);
  for (const [k, v] of configStamps) if (!v.some((t) => now - t < 60000)) configStamps.delete(k);
  for (const [k, v] of muted) if (v <= now) muted.delete(k);
}, 60000).unref();

// ---------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------
function reply(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) });
  res.end(body);
}

function readJson(req, res, limit, cb) {
  let data = "";
  let tooBig = false;
  req.on("data", (chunk) => {
    data += chunk;
    if (data.length > limit) {
      tooBig = true;
      req.destroy();
    }
  });
  req.on("end", () => {
    if (tooBig) return reply(res, 413, { error: "Request too large" });
    try {
      const parsed = JSON.parse(data);
      if (parsed === null || typeof parsed !== "object") throw new Error("not an object");
      cb(parsed);
    } catch {
      reply(res, 400, { error: "Bad JSON" });
    }
  });
  req.on("error", () => {});
}

function cleanText(value, max) {
  return String(value || "").replace(/[\u0000-\u001f\u007f]/g, " ").trim().slice(0, max);
}

function safeEqual(a, b) {
  const x = crypto.createHash("sha256").update(String(a)).digest();
  const y = crypto.createHash("sha256").update(String(b)).digest();
  return crypto.timingSafeEqual(x, y);
}

// ---------------------------------------------------------------
// Routes
// ---------------------------------------------------------------
function handleSend(req, res) {
  readJson(req, res, 2048, (data) => {
    const name = String(data.name || "").trim();
    const text = cleanText(data.text, MAX_TEXT);
    const key = name.toLowerCase();
    const now = Date.now();

    if (!NAME_RE.test(name)) return reply(res, 400, { error: "Nickname must be 2-24 letters, numbers or _ . -" });
    if (RESERVED_NAMES.has(key)) return reply(res, 400, { error: "That nickname is reserved" });
    if (!text) return reply(res, 400, { error: "Empty message" });
    if (banned.has(key)) return reply(res, 403, { error: "You are banned" });
    if ((muted.get(key) || 0) > now) return reply(res, 403, { error: "You are muted" });
    if (isFlagged(name) || isFlagged(text)) return reply(res, 400, { error: "Message blocked: please keep it clean" });
    if (!allowedToChat(key, now)) return reply(res, 429, { error: "Slow down" });

    lastSeen.set(key, now);
    const msg = pushMessage(name, text);
    reply(res, 200, { ok: true, id: msg.id });
  });
}

function handleConfigSave(req, res) {
  readJson(req, res, MAX_CODE_LENGTH + 512, (data) => {
    const name = String(data.name || "").trim();
    const code = String(data.code || "").trim();
    const key = name.toLowerCase();

    if (!NAME_RE.test(name)) return reply(res, 400, { error: "Nickname must be 2-24 letters, numbers or _ . -" });
    if (banned.has(key)) return reply(res, 403, { error: "You are banned" });
    if (!CODE_RE.test(code) || code.length > MAX_CODE_LENGTH) return reply(res, 400, { error: "Not a valid SKEED config code" });
    if (!allowedToUpload(key, Date.now())) return reply(res, 429, { error: "Too many uploads, wait a minute" });

    const id = newConfigId();
    if (!id) return reply(res, 500, { error: "Could not create an id, try again" });

    configs.set(id, { code, by: name, t: Math.floor(Date.now() / 1000) });
    while (configs.size > MAX_CONFIGS) configs.delete(configs.keys().next().value); // oldest first
    reply(res, 200, { id });
  });
}

function handleAdmin(req, res) {
  const now = Date.now();
  adminStamps = recent(adminStamps, now, 60000);
  if (adminStamps.length >= ADMIN_TRIES_PER_MINUTE) return reply(res, 429, { error: "Too many attempts" });
  adminStamps.push(now);

  readJson(req, res, 2048, (data) => {
    if (!ADMIN_KEY || !safeEqual(data.key || "", ADMIN_KEY)) return reply(res, 403, { error: "Forbidden" });

    const action = String(data.action || "");
    const name = String(data.name || "").trim();
    const key = name.toLowerCase();

    switch (action) {
      case "mute": {
        if (!NAME_RE.test(name)) return reply(res, 400, { error: "Need a valid name" });
        const minutes = Math.min(Math.max(Number(data.minutes) || 10, 1), 1440);
        muted.set(key, now + minutes * 60000);
        return reply(res, 200, { ok: true, muted: name, minutes });
      }
      case "unmute":
        muted.delete(key);
        return reply(res, 200, { ok: true });
      case "ban":
        if (!NAME_RE.test(name)) return reply(res, 400, { error: "Need a valid name" });
        banned.add(key);
        return reply(res, 200, { ok: true, banned: name });
      case "unban":
        banned.delete(key);
        return reply(res, 200, { ok: true });
      case "clear":
        messages.length = 0;
        return reply(res, 200, { ok: true });
      case "motd":
        motd = cleanText(data.text, 160);
        return reply(res, 200, { ok: true, motd });
      case "announce": {
        const text = cleanText(data.text, MAX_TEXT);
        if (!text) return reply(res, 400, { error: "Empty message" });
        pushMessage("SERVER", text);
        return reply(res, 200, { ok: true });
      }
      default:
        return reply(res, 400, { error: "Unknown action" });
    }
  });
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");
  const path = url.pathname;

  if (req.method === "GET" && path === "/") {
    return reply(res, 200, { ok: true, service: "skeed", version: VERSION });
  }

  if (req.method === "GET" && path === "/info") {
    return reply(res, 200, { name: "skeed", version: VERSION, motd, online: onlineCount(Date.now()), messages: messages.length });
  }

  if (req.method === "GET" && path === "/messages") {
    const now = Date.now();
    const who = String(url.searchParams.get("name") || "").trim();
    if (NAME_RE.test(who) && !banned.has(who.toLowerCase())) lastSeen.set(who.toLowerCase(), now);

    const after = Number(url.searchParams.get("after")) || 0;
    const last = nextId - 1;
    const base = { last, online: onlineCount(now), motd };
    if (after > last) return reply(res, 200, { ...base, messages: [] }); // server restarted

    let out = messages.filter((m) => m.id > after);
    if (after === 0) out = out.slice(-HISTORY_ON_JOIN);
    return reply(res, 200, { ...base, messages: out.slice(0, 50) });
  }

  if (req.method === "POST" && path === "/send") return handleSend(req, res);
  if (req.method === "POST" && path === "/config/save") return handleConfigSave(req, res);
  if (req.method === "POST" && path === "/admin") return handleAdmin(req, res);

  if (req.method === "GET" && path.startsWith("/config/")) {
    const id = path.slice("/config/".length).toLowerCase();
    const cfg = /^[a-z0-9]{4,12}$/.test(id) ? configs.get(id) : null;
    if (!cfg) return reply(res, 404, { error: "Config not found" });
    return reply(res, 200, cfg);
  }

  reply(res, 404, { error: "Not found" });
});

server.listen(PORT, () => console.log(`skeed server ${VERSION} listening on :${PORT}`));
