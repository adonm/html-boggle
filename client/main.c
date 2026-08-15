/*******************************************************************************
 * Boggle - a multiplayer word game in the browser.
 *
 * Rendering:  raylib 5.5 compiled to WebAssembly with emscripten.
 * Networking: iroh gossip (Rust wasm, see net/) bridged through glue.js.
 *             Everyone entering the same room code joins the same gossip
 *             channel; the board is derived deterministically from the room
 *             code so all players see the same dice.
 *
 * Roles: the member with the lexicographically smallest node id is the "host":
 *        it starts rounds, validates word claims and publishes authoritative
 *        state. All clients apply identical rules, so host handoff is seamless.
 ******************************************************************************/

#include "raylib.h"
#include "jsmn.h"
#include <emscripten/emscripten.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* forward declarations */
static void doJoin(void);
static void applyStartLocally(void);
static void sendState(void);

#define GAME_W 960
#define GAME_H 600
#define ROUND_MS 180000.0
#define HELLO_INTERVAL_MS 5000.0
#define PLAYER_TIMEOUT_MS 45000.0
#define STATE_INTERVAL_MS 10000.0
#define JOIN_TIMEOUT_MS 15000.0
#define MAX_PLAYERS 8
#define MAX_WORDS 96
#define MAX_WORD_LEN 20
#define MAX_NAME_LEN 24
#define MAX_ROOM_LEN 32
#define MAX_TOKENS 8192

typedef enum { ST_LOBBY, ST_JOINING, ST_ROOM, ST_PLAY, ST_RESULTS } Phase;

typedef struct {
    char id[64]; /* iroh node id */
    char name[40];
    int score;
    int wordsN;
    char words[MAX_WORDS][MAX_WORD_LEN];
    double lastSeen; /* js clock, ms */
    int isMe;
} Player;

/* ------------------------------------------------------------------ state */
static Phase phase = ST_LOBBY;
static Player players[MAX_PLAYERS];
static int playersN = 0;
static char meId[64] = "";
static char myName[MAX_NAME_LEN] = "";
static char room[MAX_ROOM_LEN] = "";
static char board[16][4]; /* tile letters, "qu" occupies one tile */
static int path[16];
static int pathLen = 0;
static char curWord[64] = "";
static double deadlineMs = 0;
static int roundN = 0;
static char toast[192] = "";
static double toastUntil = 0;
static double lastHello = 0;
static double lastState = 0;
static double joinStartedAt = 0;
static char inputName[MAX_NAME_LEN] = "";
static char inputRoom[MAX_ROOM_LEN] = "";
static int focusField = 0; /* 0 = name, 1 = room */
static char pendingWord[MAX_WORD_LEN] = ""; /* claim awaiting host ack */
static double pendingSentAt = 0;

/* dictionary (embedded words.txt, sorted) */
static char *dictData = NULL;
static char **dictWords = NULL;
static int dictCount = 0;

/* ------------------------------------------------------------------ js glue */
EM_JS(void, js_join, (const char *room, const char *name), {
  const g = window.__boggleGlue;
  if (g) g.join(UTF8ToString(room), UTF8ToString(name));
  else console.warn("[boggle] glue not loaded yet");
});

EM_JS(void, js_send, (const char *json), {
  const g = window.__boggleGlue;
  if (g) g.send(UTF8ToString(json));
});

EM_JS(double, js_now, (void), { return Date.now(); });

/* --------------------------------------------------------------- json (jsmn) */
static jsmntok_t g_toks[MAX_TOKENS];

static int json_parse(const char *s, int *outN) {
    jsmn_parser p;
    jsmn_init(&p);
    int n = jsmn_parse(&p, s, strlen(s), g_toks, MAX_TOKENS);
    if (n < 0) return -1;
    *outN = n;
    return 0;
}

/* Return token index of the value for `key` in object `obj`, or -1. */
static int jfind(const char *s, int n, int obj, const char *key) {
    jsmntok_t *t = g_toks;
    if (t[obj].type != JSMN_OBJECT) return -1;
    for (int i = 0; i < t[obj].size; i++) {
        jsmntok_t *k = &t[obj + 1 + 2 * i];
        if (k->type == JSMN_STRING && (size_t)(k->end - k->start) == strlen(key) &&
            strncmp(s + k->start, key, k->end - k->start) == 0)
            return obj + 2 + 2 * i;
    }
    return -1;
}

static void jcopy(const char *s, jsmntok_t *tok, char *out, int cap) {
    int len = tok->end - tok->start;
    if (len > cap - 1) len = cap - 1;
    memcpy(out, s + tok->start, len);
    out[len] = 0;
}

static int jint(const char *s, jsmntok_t *tok) {
    char buf[32];
    jcopy(s, tok, buf, sizeof buf);
    return (int)strtol(buf, NULL, 10);
}

static double jdouble(const char *s, jsmntok_t *tok) {
    char buf[32];
    jcopy(s, tok, buf, sizeof buf);
    return strtod(buf, NULL);
}

/* -------------------------------------------------------------- small utils */
static void setToast(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(toast, sizeof toast, fmt, ap);
    va_end(ap);
    toastUntil = js_now() + 2600.0;
}

/* ------------------------------------------------------------------ players */
static Player *playerById(const char *id) {
    for (int i = 0; i < playersN; i++)
        if (strcmp(players[i].id, id) == 0) return &players[i];
    return NULL;
}

static Player *addPlayer(const char *id, const char *name, int isMe) {
    if (playersN >= MAX_PLAYERS) return NULL;
    Player *p = &players[playersN++];
    memset(p, 0, sizeof *p);
    strncpy(p->id, id, sizeof p->id - 1);
    strncpy(p->name, name, sizeof p->name - 1);
    p->lastSeen = js_now();
    p->isMe = isMe;
    return p;
}

static void removePlayerAt(int idx) {
    memmove(&players[idx], &players[idx + 1], (size_t)(playersN - idx - 1) * sizeof(Player));
    playersN--;
}

/* Host = member with the lexicographically smallest node id (deterministic). */
static const char *hostId(void) {
    const char *best = NULL;
    for (int i = 0; i < playersN; i++)
        if (!best || strcmp(players[i].id, best) < 0) best = players[i].id;
    return best;
}

static int iAmHost(void) {
    const char *h = hostId();
    return h != NULL && strcmp(h, meId) == 0;
}

/* ------------------------------------------------------------------- words */
static int scoreForLen(int len) {
    if (len <= 4) return 1;
    if (len == 5) return 2;
    if (len == 6) return 3;
    if (len == 7) return 5;
    return 11;
}

static int playerHasWord(const Player *p, const char *w) {
    for (int i = 0; i < p->wordsN; i++)
        if (strcmp(p->words[i], w) == 0) return 1;
    return 0;
}

static int anyoneHasWord(const char *w, const char *exceptId) {
    for (int i = 0; i < playersN; i++)
        if (strcmp(players[i].id, exceptId) != 0 && playerHasWord(&players[i], w)) return 1;
    return 0;
}

static void addWordTo(Player *p, const char *w) {
    if (p->wordsN >= MAX_WORDS) {
        memmove(p->words[0], p->words[1], (MAX_WORDS - 1) * MAX_WORD_LEN);
        p->wordsN = MAX_WORDS - 1;
    }
    strncpy(p->words[p->wordsN], w, MAX_WORD_LEN - 1);
    p->words[p->wordsN][MAX_WORD_LEN - 1] = 0;
    p->wordsN++;
    p->score += scoreForLen((int)strlen(w));
}

static int dictHas(const char *w) {
    int lo = 0, hi = dictCount - 1;
    while (lo <= hi) {
        int mid = lo + (hi - lo) / 2;
        int cmp = strcmp(dictWords[mid], w);
        if (cmp == 0) return 1;
        if (cmp < 0) lo = mid + 1;
        else hi = mid - 1;
    }
    return 0;
}

static int visited[16];

static int dfsWord(const char *w, int wlen, int idx, int pos) {
    if (idx == wlen) return 1;
    int r = pos / 4, c = pos % 4;
    for (int dr = -1; dr <= 1; dr++) {
        for (int dc = -1; dc <= 1; dc++) {
            if (dr == 0 && dc == 0) continue;
            int nr = r + dr, nc = c + dc;
            if (nr < 0 || nr > 3 || nc < 0 || nc > 3) continue;
            int np = nr * 4 + nc;
            if (visited[np]) continue;
            const char *tile = board[np];
            int tl = (int)strlen(tile);
            if (idx + tl > wlen) continue;
            if (strncmp(w + idx, tile, tl) != 0) continue;
            visited[np] = 1;
            if (dfsWord(w, wlen, idx + tl, np)) return 1;
            visited[np] = 0;
        }
    }
    return 0;
}

/* Can `w` be formed from adjacent tiles (each tile at most once)? */
static int wordOnBoard(const char *w) {
    int wlen = (int)strlen(w);
    memset(visited, 0, sizeof visited);
    for (int i = 0; i < 16; i++) {
        int tl = (int)strlen(board[i]);
        if (tl == 0 || tl > wlen) continue;
        if (strncmp(w, board[i], tl) != 0) continue;
        visited[i] = 1;
        if (dfsWord(w, wlen, tl, i)) return 1;
        visited[i] = 0;
    }
    return 0;
}

/* --------------------------------------------------------------- dictionary */
static void loadDict(void) {
    char *data = LoadFileText("/words.txt");
    if (!data) {
        TraceLog(LOG_WARNING, "words.txt not found, dictionary disabled");
        return;
    }
    int count = 0;
    for (int i = 0; data[i]; i++)
        if (data[i] == '\n') count++;
    dictWords = (char **)MemAlloc(sizeof(char *) * (size_t)count);
    char *p = data;
    int n = 0;
    for (;;) {
        char *nl = strchr(p, '\n');
        if (!nl) break;
        *nl = 0;
        size_t l = strlen(p);
        if (l >= 3 && l <= 16) dictWords[n++] = p;
        p = nl + 1;
        if (!*p) break;
    }
    dictCount = n;
    dictData = data;
    TraceLog(LOG_INFO, "loaded %d dictionary words", dictCount);
}

/* --------------------------------------------------------------- messaging */
static void sendJson(const char *json) { js_send(json); }

static void sendHello(void) {
    char buf[256];
    snprintf(buf, sizeof buf, "{\"t\":\"hello\",\"node\":\"%s\",\"name\":\"%s\"}", meId, myName);
    sendJson(buf);
}

static void sendAward(const char *word, const char *node, int points) {
    char buf[256];
    snprintf(buf, sizeof buf, "{\"t\":\"award\",\"node\":\"%s\",\"word\":\"%s\",\"points\":%d}",
             node, word, points);
    sendJson(buf);
}

static void sendReject(const char *word, const char *node, const char *reason) {
    char buf[256];
    snprintf(buf, sizeof buf, "{\"t\":\"reject\",\"node\":\"%s\",\"word\":\"%s\",\"reason\":\"%s\"}",
             node, word, reason);
    sendJson(buf);
}

static void sendClaim(const char *word) {
    char buf[256];
    snprintf(buf, sizeof buf, "{\"t\":\"claim\",\"node\":\"%s\",\"word\":\"%s\",\"name\":\"%s\"}",
             meId, word, myName);
    sendJson(buf);
}

static void sendStart(void) {
    deadlineMs = js_now() + ROUND_MS;
    roundN++;
    char buf[256];
    snprintf(buf, sizeof buf,
             "{\"t\":\"start\",\"node\":\"%s\",\"deadline\":%.0f,\"round\":%d}", meId, deadlineMs,
             roundN);
    sendJson(buf);
    applyStartLocally();
}

/* Authoritative snapshot; also used as the round-end tally. */
static void sendState(void) {
    static char buf[32768];
    int off = 0;
    const char *ph = phase == ST_PLAY ? "play" : (phase == ST_RESULTS ? "results" : "room");
    off += snprintf(buf + off, sizeof buf - off,
                    "{\"t\":\"state\",\"node\":\"%s\",\"phase\":\"%s\",\"deadline\":%.0f,"
                    "\"round\":%d,\"players\":[",
                    meId, ph, deadlineMs, roundN);
    for (int i = 0; i < playersN; i++) {
        Player *p = &players[i];
        off += snprintf(buf + off, sizeof buf - off, "%s{\"node\":\"%s\",\"name\":\"%s\",\"score\":%d,\"words\":[",
                        i ? "," : "", p->id, p->name, p->score);
        for (int j = 0; j < p->wordsN; j++)
            off += snprintf(buf + off, sizeof buf - off, "%s\"%s\"", j ? "," : "", p->words[j]);
        off += snprintf(buf + off, sizeof buf - off, "]}");
    }
    off += snprintf(buf + off, sizeof buf - off, "]}");
    sendJson(buf);
}

/* ---------------------------------------------------------------- selection */
static void clearSel(void) {
    pathLen = 0;
    curWord[0] = 0;
}

static void pushTile(int idx) {
    if (pathLen >= 16 || !board[idx][0]) return;
    for (int i = 0; i < pathLen; i++)
        if (path[i] == idx) return;
    if (pathLen > 0) {
        int last = path[pathLen - 1];
        int dr = abs(last / 4 - idx / 4), dc = abs(last % 4 - idx % 4);
        if (dr > 1 || dc > 1) return;
    }
    path[pathLen++] = idx;
    size_t used = strlen(curWord);
    strncpy(curWord + used, board[idx], sizeof curWord - used - 1);
}

static void popTile(void) {
    if (pathLen == 0) return;
    int idx = path[--pathLen];
    int tl = (int)strlen(board[idx]);
    int cl = (int)strlen(curWord);
    if (cl >= tl) curWord[cl - tl] = 0;
}

/* -------------------------------------------------------------------- round */
static void applyStartLocally(void) {
    for (int i = 0; i < playersN; i++) players[i].wordsN = 0;
    clearSel();
    pendingWord[0] = 0;
    phase = ST_PLAY;
    setToast("Round %d - find words!", roundN);
}

static void checkRoundEnd(void) {
    if (phase != ST_PLAY) return;
    if (js_now() >= deadlineMs) {
        phase = ST_RESULTS;
        setToast("Round over!");
        if (iAmHost()) sendState();
    }
}

static void submitWord(void) {
    if (phase != ST_PLAY || pathLen == 0) return;
    Player *me = playerById(meId);
    if (!me) return;
    int wlen = (int)strlen(curWord);
    if (wlen < 3) {
        setToast("Words need at least 3 letters");
        clearSel();
        return;
    }
    if (playerHasWord(me, curWord)) {
        setToast("You already found \"%s\"", curWord);
        clearSel();
        return;
    }
    if (anyoneHasWord(curWord, meId)) {
        setToast("\"%s\" is already taken", curWord);
        clearSel();
        return;
    }
    if (!dictHas(curWord)) {
        setToast("\"%s\" is not in the dictionary", curWord);
        clearSel();
        return;
    }
    if (!wordOnBoard(curWord)) {
        setToast("\"%s\" is not on the board", curWord);
        clearSel();
        return;
    }
    if (iAmHost()) {
        addWordTo(me, curWord);
        sendAward(curWord, meId, scoreForLen(wlen));
        setToast("+%d for \"%s\"!", scoreForLen(wlen), curWord);
    } else {
        addWordTo(me, curWord);
        strncpy(pendingWord, curWord, sizeof pendingWord - 1);
        pendingSentAt = js_now();
        sendClaim(curWord);
        setToast("Submitted \"%s\"", curWord);
    }
    clearSel();
}

/* ------------------------------------------------------------- event intake */
static void applyState(const char *json, int n) {
    jsmntok_t *t = g_toks;

    /* rebuild the players array from the host's snapshot */
    int ptok = jfind(json, n, 0, "players");
    if (ptok >= 0 && t[ptok].type == JSMN_ARRAY) {
        Player tmp[MAX_PLAYERS];
        int nn = 0;
        for (int i = 0; i < t[ptok].size && nn < MAX_PLAYERS; i++) {
            int pobj = ptok + 1 + i;
            if (t[pobj].type != JSMN_OBJECT) continue;
            Player *np = &tmp[nn];
            memset(np, 0, sizeof *np);
            int idTok = jfind(json, n, pobj, "node");
            int nameTok = jfind(json, n, pobj, "name");
            int scoreTok = jfind(json, n, pobj, "score");
            int wordsTok = jfind(json, n, pobj, "words");
            if (idTok < 0) continue;
            jcopy(json, &t[idTok], np->id, sizeof np->id);
            if (nameTok >= 0) jcopy(json, &t[nameTok], np->name, sizeof np->name);
            if (scoreTok >= 0) np->score = jint(json, &t[scoreTok]);
            np->isMe = strcmp(np->id, meId) == 0;
            if (wordsTok >= 0 && t[wordsTok].type == JSMN_ARRAY) {
                for (int j = 0; j < t[wordsTok].size && np->wordsN < MAX_WORDS; j++)
                    jcopy(json, &t[wordsTok + 1 + j], np->words[np->wordsN++], MAX_WORD_LEN);
            }
            np->lastSeen = js_now();
            nn++;
        }
        memcpy(players, tmp, sizeof(Player) * (size_t)nn);
        playersN = nn;
        if (!playerById(meId)) {
            Player *me = addPlayer(meId, myName, 1);
            (void)me;
        }
    }

    int phTok = jfind(json, n, 0, "phase");
    if (phTok >= 0) {
        char ph[16];
        jcopy(json, &t[phTok], ph, sizeof ph);
        if (strcmp(ph, "play") == 0) {
            phase = ST_PLAY;
            clearSel();
        } else if (strcmp(ph, "results") == 0) {
            phase = ST_RESULTS;
        } else {
            phase = ST_ROOM;
        }
    }
    int dlTok = jfind(json, n, 0, "deadline");
    if (dlTok >= 0) deadlineMs = jdouble(json, &t[dlTok]);
    int rTok = jfind(json, n, 0, "round");
    if (rTok >= 0) roundN = jint(json, &t[rTok]);
}

void EMSCRIPTEN_KEEPALIVE boggle_on_event(const char *json) {
    int n;
    if (json_parse(json, &n) < 0) {
        TraceLog(LOG_WARNING, "unparseable event");
        return;
    }
    jsmntok_t *t = g_toks;
    char kind[16] = "", type[16] = "", node[64] = "", name[40] = "", word[MAX_WORD_LEN] = "";
    int kindTok = jfind(json, n, 0, "kind");
    int typeTok = jfind(json, n, 0, "t");
    int nodeTok = jfind(json, n, 0, "node");
    int nameTok = jfind(json, n, 0, "name");
    if (kindTok >= 0) jcopy(json, &t[kindTok], kind, sizeof kind);
    if (typeTok >= 0) jcopy(json, &t[typeTok], type, sizeof type);
    if (nodeTok >= 0) jcopy(json, &t[nodeTok], node, sizeof node);
    if (nameTok >= 0) jcopy(json, &t[nameTok], name, sizeof name);

    /* glue-level events */
    if (kind[0]) {
        if (strcmp(kind, "joined") == 0) {
            int roomTok = jfind(json, n, 0, "room");
            if (roomTok >= 0) jcopy(json, &t[roomTok], room, sizeof room);
            strncpy(meId, node, sizeof meId - 1);
            playersN = 0;
            addPlayer(meId, myName, 1);
            phase = ST_ROOM;
            lastHello = 0;
            sendHello();
            setToast("Joined room \"%s\"", room);
            return;
        }
        if (strcmp(kind, "joinFail") == 0) {
            int reasonTok = jfind(json, n, 0, "reason");
            char r[192] = "could not join";
            if (reasonTok >= 0) jcopy(json, &t[reasonTok], r, sizeof r);
            phase = ST_LOBBY;
            setToast("%s", r);
            return;
        }
        if (strcmp(kind, "up") == 0) {
            if (node[0] && strcmp(node, meId) != 0) {
                Player *p = playerById(node);
                if (!p && playersN < MAX_PLAYERS) {
                    addPlayer(node, "", 0);
                    if (iAmHost()) sendState();
                }
                sendHello();
            }
            return;
        }
        if (strcmp(kind, "down") == 0) {
            if (node[0]) {
                Player *p = playerById(node);
                if (p) {
                    setToast("%s left", p->name[0] ? p->name : "A player");
                    for (int i = 0; i < playersN; i++)
                        if (&players[i] == p) {
                            removePlayerAt(i);
                            break;
                        }
                    if (iAmHost()) sendState();
                }
            }
            return;
        }
        if (strcmp(kind, "lagged") == 0) {
            setToast("Network hiccup - some messages may be missing");
            return;
        }
        return;
    }

    /* app messages (type = "t") */
    if (strcmp(type, "hello") == 0) {
        if (!node[0] || strcmp(node, meId) == 0) return;
        Player *p = playerById(node);
        if (!p) {
            if (playersN >= MAX_PLAYERS) return;
            p = addPlayer(node, name, 0);
            if (iAmHost()) sendState();
        } else if (name[0]) {
            strncpy(p->name, name, sizeof p->name - 1);
        }
        p->lastSeen = js_now();
        return;
    }
    if (strcmp(type, "bye") == 0) {
        Player *p = playerById(node);
        if (p) {
            setToast("%s left", p->name[0] ? p->name : "A player");
            for (int i = 0; i < playersN; i++)
                if (&players[i] == p) {
                    removePlayerAt(i);
                    break;
                }
            if (iAmHost()) sendState();
        }
        return;
    }
    if (strcmp(type, "start") == 0) {
        int dlTok = jfind(json, n, 0, "deadline");
        int rTok = jfind(json, n, 0, "round");
        if (dlTok >= 0) deadlineMs = jdouble(json, &t[dlTok]);
        if (rTok >= 0) roundN = jint(json, &t[rTok]);
        applyStartLocally();
        return;
    }
    if (strcmp(type, "claim") == 0) {
        if (!iAmHost()) return; /* only the host arbitrates */
        int wordTok = jfind(json, n, 0, "word");
        if (wordTok < 0) return;
        jcopy(json, &t[wordTok], word, sizeof word);
        Player *p = playerById(node);
        if (!p || phase != ST_PLAY) return;
        int wlen = (int)strlen(word);
        if (wlen < 3 || wlen > 16) {
            sendReject(word, node, "invalid");
            return;
        }
        if (playerHasWord(p, word)) {
            /* idempotent re-ack: the award got lost in transit, resend it */
            sendAward(word, node, scoreForLen(wlen));
            return;
        }
        if (anyoneHasWord(word, node)) {
            sendReject(word, node, "taken");
            return;
        }
        if (!dictHas(word)) {
            sendReject(word, node, "invalid");
            return;
        }
        if (!wordOnBoard(word)) {
            sendReject(word, node, "invalid");
            return;
        }
        addWordTo(p, word);
        sendAward(word, node, scoreForLen(wlen));
        setToast("%s found \"%s\"", p->name[0] ? p->name : "Someone", word);
        return;
    }
    if (strcmp(type, "award") == 0) {
        int wordTok = jfind(json, n, 0, "word");
        int ptsTok = jfind(json, n, 0, "points");
        if (wordTok < 0) return;
        jcopy(json, &t[wordTok], word, sizeof word);
        Player *p = playerById(node);
        if (!p) return;
        if (phase != ST_PLAY) return;
        if (playerHasWord(p, word)) {
            /* duplicate delivery of an award we already applied */
            if (p->isMe && strcmp(word, pendingWord) == 0) pendingWord[0] = 0;
            return;
        }
        addWordTo(p, word);
        if (p->isMe && strcmp(word, pendingWord) == 0) pendingWord[0] = 0;
        if (!p->isMe) {
            int pts = ptsTok >= 0 ? jint(json, &t[ptsTok]) : scoreForLen((int)strlen(word));
            setToast("%s: \"%s\" +%d", p->name[0] ? p->name : "Someone", word, pts);
        }
        return;
    }
    if (strcmp(type, "reject") == 0) {
        if (strcmp(node, meId) != 0) return;
        int wordTok = jfind(json, n, 0, "word");
        int reasonTok = jfind(json, n, 0, "reason");
        if (wordTok < 0) return;
        jcopy(json, &t[wordTok], word, sizeof word);
        if (strcmp(word, pendingWord) == 0) pendingWord[0] = 0;
        char why[32] = "rejected";
        if (reasonTok >= 0) jcopy(json, &t[reasonTok], why, sizeof why);
        Player *me = playerById(meId);
        if (me) {
            for (int i = 0; i < me->wordsN; i++) {
                if (strcmp(me->words[i], word) == 0) {
                    memmove(me->words[i], me->words[i + 1],
                            (size_t)(me->wordsN - i - 1) * MAX_WORD_LEN);
                    me->wordsN--;
                    break;
                }
            }
        }
        setToast("\"%s\" rejected: %s", word, why);
        return;
    }
    if (strcmp(type, "state") == 0) {
        applyState(json, n);
        return;
    }
}

void EMSCRIPTEN_KEEPALIVE boggle_set_board(const char *letters) {
    char buf[96];
    strncpy(buf, letters, sizeof buf - 1);
    buf[sizeof buf - 1] = 0;
    int i = 0;
    char *tok = strtok(buf, ",");
    while (tok && i < 16) {
        strncpy(board[i], tok, 3);
        board[i][3] = 0;
        i++;
        tok = strtok(NULL, ",");
    }
    for (; i < 16; i++) board[i][0] = 0;
}

/* Debug hook for tests/tools. Format:
 * "phase=N players=N room=X me=Y total=N words=N cur=<word> toast=<msg> p<N>=<score>,<words>..." */
EMSCRIPTEN_KEEPALIVE const char *boggle_dbg(void) {
    static char buf[1024];
    int total = 0;
    int myWords = 0;
    for (int i = 0; i < playersN; i++) {
        total += players[i].score;
        if (players[i].isMe) myWords = players[i].wordsN;
    }
    int off = snprintf(buf, sizeof buf, "phase=%d players=%d room=%s me=%s total=%d words=%d cur=%s toast=%s",
                       (int)phase, playersN, room, meId, total, myWords, curWord, toast);
    for (int i = 0; i < playersN; i++) {
        off += snprintf(buf + off, sizeof buf - off, " p%d=%d,%d", i, players[i].score, players[i].wordsN);
    }
    return buf;
}

static int findPathCells(const char *w, int wlen, int idx, int pos, int out[16], int outN) {
    if (idx == wlen) return 1;
    for (int i = 0; i < 16; i++) {
        if (visited[i]) continue;
        if (pos >= 0) {
            int dr = abs(i / 4 - pos / 4), dc = abs(i % 4 - pos % 4);
            if (dr > 1 || dc > 1) continue;
        }
        int tl = (int)strlen(board[i]);
        if (tl == 0 || idx + tl > wlen) continue;
        if (strncmp(w + idx, board[i], tl) != 0) continue;
        visited[i] = 1;
        out[outN] = i;
        if (findPathCells(w, wlen, idx + tl, i, out, outN + 1)) return 1;
        visited[i] = 0;
    }
    return 0;
}

/* Test/debug helper: build a valid tile path for `word` and submit it, as if
 * the player had clicked the tiles and pressed Enter. */
EMSCRIPTEN_KEEPALIVE void boggle_debug_submit(const char *word) {
    if (phase != ST_PLAY || !word[0]) return;
    clearSel();
    int out[16];
    memset(visited, 0, sizeof visited);
    int wlen = (int)strlen(word);
    if (!findPathCells(word, wlen, 0, -1, out, 0)) return;
    int total = 0, n = 0;
    for (n = 0; n < 16 && total < wlen; n++) total += (int)strlen(board[out[n]]);
    for (int i = 0; i < n; i++) pushTile(out[i]);
    submitWord();
}

/* ---------------------------------------------------------------------- ui */
#define C_BG (Color){20, 20, 32, 255}
#define C_PANEL (Color){30, 30, 46, 255}
#define C_PANEL2 (Color){44, 48, 70, 255}
#define C_ACCENT (Color){240, 184, 74, 255}
#define C_ACCENT2 (Color){96, 200, 120, 255}
#define C_TEXT (Color){228, 228, 238, 255}
#define C_DIM (Color){148, 148, 166, 255}
#define C_RED (Color){224, 92, 92, 255}

static int uiButton(Rectangle r, const char *label, int enabled) {
    Color col = enabled ? C_ACCENT : (Color){56, 56, 72, 255};
    Color txt = enabled ? (Color){24, 24, 34, 255} : C_DIM;
    if (enabled && CheckCollisionPointRec(GetMousePosition(), r)) {
        col = (Color){255, 206, 112, 255};
        if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) return 1;
    }
    DrawRectangleRounded(r, 0.25f, 12, col);
    int tw = MeasureText(label, 20);
    DrawText(label, (int)(r.x + (r.width - tw) / 2), (int)(r.y + (r.height - 20) / 2), 20, txt);
    return 0;
}

static void drawCentered(const char *s, int y, int size, Color c) {
    DrawText(s, (GAME_W - MeasureText(s, size)) / 2, y, size, c);
}

static void drawInput(Rectangle r, const char *label, const char *value, int focused) {
    DrawText(label, (int)r.x, (int)r.y - 22, 16, C_DIM);
    DrawRectangleRounded(r, 0.2f, 12, C_PANEL2);
    if (focused) DrawRectangleRoundedLines(r, 0.2f, 12, C_ACCENT);
    else DrawRectangleRoundedLines(r, 0.2f, 12, C_PANEL2);
    DrawText(value, (int)r.x + 12, (int)(r.y + (r.height - 22) / 2), 22, C_TEXT);
    if (focused && ((int)(GetTime() * 2) % 2 == 0)) {
        int cx = (int)r.x + 14 + MeasureText(value, 22);
        DrawRectangle(cx, (int)r.y + 10, 2, (int)r.height - 20, C_ACCENT);
    }
}

static void drawToast(void) {
    if (js_now() >= toastUntil || !toast[0]) return;
    int w = MeasureText(toast, 18);
    Rectangle r = {(GAME_W - w) / 2.0f - 14, GAME_H - 52.0f, w + 28.0f, 34.0f};
    DrawRectangleRounded(r, 0.4f, 12, (Color){0, 0, 0, 170});
    DrawText(toast, (int)r.x + 14, (int)r.y + 8, 18, C_TEXT);
}

static void drawTile(int idx, int selectedOrder) {
    int r = idx / 4, c = idx % 4;
    float x = 36.0f + c * 91.0f;
    float y = 110.0f + r * 91.0f;
    Rectangle rect = {x, y, 82, 82};
    Color col = selectedOrder > 0 ? C_ACCENT : C_PANEL2;
    if (CheckCollisionPointRec(GetMousePosition(), rect))
        col = selectedOrder > 0 ? (Color){255, 210, 120, 255} : (Color){62, 68, 96, 255};
    DrawRectangleRounded(rect, 0.22f, 12, col);
    char label[4];
    strncpy(label, board[idx], 3);
    label[0] = (char)(label[0] >= 'a' && label[0] <= 'z' ? label[0] - 32 : label[0]);
    int tw = MeasureText(label, 34);
    DrawText(label, (int)(rect.x + (rect.width - tw) / 2),
             (int)(rect.y + (rect.height - 34) / 2), 34,
             selectedOrder > 0 ? (Color){24, 24, 34, 255} : C_TEXT);
    if (selectedOrder > 0) {
        char ord[4];
        snprintf(ord, sizeof ord, "%d", selectedOrder);
        DrawText(ord, (int)rect.x + 6, (int)rect.y + 4, 14, (Color){24, 24, 34, 255});
    }
}

static void drawBoardAndWord(void) {
    for (int i = 0; i < 16; i++) {
        int order = 0;
        for (int j = 0; j < pathLen; j++)
            if (path[j] == i) order = j + 1;
        drawTile(i, order);
    }
    /* current word */
    char buf[80];
    snprintf(buf, sizeof buf, "%s", curWord[0] ? curWord : "click tiles to spell a word");
    Color col = curWord[0] ? C_ACCENT : C_DIM;
    DrawText(buf, 40, 496, 24, col);
    DrawText("ENTER submit  ·  BACKSPACE undo  ·  ESC clear", 40, 528, 14, C_DIM);
}

static void drawPlayersPanel(void) {
    Rectangle panel = {420, 96, 504, 380};
    DrawRectangleRounded(panel, 0.06f, 12, C_PANEL);
    DrawText("PLAYERS", 436, 108, 14, C_DIM);
    int y = 132;
    for (int i = 0; i < playersN; i++) {
        Player *p = &players[i];
        int isHost = strcmp(p->id, hostId()) == 0;
        char line[96];
        snprintf(line, sizeof line, "%s%s%s", p->isMe ? "YOU - " : "",
                 p->name[0] ? p->name : "...", isHost ? "  (HOST)" : "");
        DrawText(line, 436, y, 18, p->isMe ? C_ACCENT2 : C_TEXT);
        char score[32];
        snprintf(score, sizeof score, "%d pts · %d words", p->score, p->wordsN);
        int sw = MeasureText(score, 16);
        DrawText(score, (int)(panel.x + panel.width - sw - 16), y + 1, 16, C_DIM);
        y += 26;
    }
    /* my found words */
    Player *me = playerById(meId);
    if (me) {
        DrawRectangle(436, y + 6, (int)panel.width - 32, 1, C_PANEL2);
        char head[64];
        snprintf(head, sizeof head, "YOUR WORDS (%d)", me->wordsN);
        DrawText(head, 436, y + 16, 14, C_DIM);
        int shown = 0;
        int yy = y + 40;
        for (int i = me->wordsN - 1; i >= 0 && shown < 8; i--) {
            DrawText(me->words[i], 436, yy, 16, C_TEXT);
            yy += 20;
            shown++;
        }
        if (me->wordsN > shown) {
            char more[32];
            snprintf(more, sizeof more, "+%d more", me->wordsN - shown);
            DrawText(more, 436, yy, 14, C_DIM);
        }
    }
}

static void drawLobby(void) {
    drawCentered("BOGGLE", 96, 72, C_ACCENT);
    drawCentered("multiplayer word game  ·  raylib x iroh", 168, 16, C_DIM);

    Rectangle panel = {280, 218, 400, 284};
    DrawRectangleRounded(panel, 0.08f, 12, C_PANEL);

    Rectangle nameRect = {308, 262, 344, 44};
    Rectangle roomRect = {308, 352, 344, 44};
    drawInput(nameRect, "YOUR NAME", inputName, focusField == 0);
    drawInput(roomRect, "ROOM CODE", inputRoom, focusField == 1);

    if (uiButton((Rectangle){308, 424, 344, 44}, "JOIN ROOM", 1)) {
        doJoin();
    }
    DrawText("Everyone entering the same room code joins the", 322, 476, 12, C_DIM);
    DrawText("same iroh gossip channel. No accounts, P2P.", 322, 490, 12, C_DIM);
}

static void drawJoining(void) {
    drawCentered("Joining room...", 260, 28, C_TEXT);
    drawCentered("contacting peers through iroh gossip", 300, 14, C_DIM);
}

static void drawRoom(void) {
    char head[96];
    snprintf(head, sizeof head, "ROOM  %s", room);
    drawCentered(head, 60, 30, C_ACCENT);
    drawCentered("players who enter this code join the same game", 96, 14, C_DIM);

    Rectangle panel = {280, 150, 400, 250};
    DrawRectangleRounded(panel, 0.08f, 12, C_PANEL);
    for (int i = 0; i < playersN; i++) {
        Player *p = &players[i];
        int isHost = strcmp(p->id, hostId()) == 0;
        char line[96];
        snprintf(line, sizeof line, "%s  %s%s", p->isMe ? ">" : " ",
                 p->name[0] ? p->name : "connecting...", isHost ? "   (HOST)" : "");
        DrawText(line, 308, 178 + i * 28, 20, p->isMe ? C_ACCENT2 : C_TEXT);
    }
    char count[64];
    snprintf(count, sizeof count, "%d player%s in room", playersN, playersN == 1 ? "" : "s");
    drawCentered(count, 178 + playersN * 28 + 14, 14, C_DIM);

    if (iAmHost()) {
        if (uiButton((Rectangle){356, 430, 248, 44}, "START ROUND", playersN >= 1)) {
            sendStart();
        }
    } else {
        drawCentered("waiting for the host to start...", 444, 16, C_DIM);
    }
    drawCentered("find 3+ letter words in adjacent tiles (any direction)", 560, 13, C_DIM);
}

static void drawPlay(void) {
    /* header */
    char head[128];
    double remaining = deadlineMs - js_now();
    if (remaining < 0) remaining = 0;
    int mins = (int)(remaining / 60000.0);
    int secs = (int)((remaining - mins * 60000.0) / 1000.0);
    Color tcol = remaining < 10000 ? C_RED : C_ACCENT;
    snprintf(head, sizeof head, "ROOM %s   ·   ROUND %d   ·   %d:%02d", room, roundN, mins, secs);
    drawCentered(head, 24, 26, tcol);
    int w = MeasureText(head, 26);
    if (remaining > 0 && remaining <= ROUND_MS) {
        DrawRectangle((GAME_W - w) / 2, 56, (int)(w * remaining / ROUND_MS), 4, tcol);
    }

    drawBoardAndWord();
    drawPlayersPanel();

    Player *me = playerById(meId);
    if (me) {
        char sc[48];
        snprintf(sc, sizeof sc, "your score: %d", me->score);
        int sw = MeasureText(sc, 18);
        DrawText(sc, GAME_W - sw - 20, 24, 18, C_ACCENT2);
    }
}

static void drawResults(void) {
    char head[64];
    snprintf(head, sizeof head, "ROUND %d OVER", roundN);
    drawCentered(head, 44, 30, C_ACCENT);

    /* rank by score */
    int order[MAX_PLAYERS];
    for (int i = 0; i < playersN; i++) order[i] = i;
    for (int i = 0; i < playersN; i++)
        for (int j = i + 1; j < playersN; j++)
            if (players[order[j]].score > players[order[i]].score) {
                int tmp = order[i];
                order[i] = order[j];
                order[j] = tmp;
            }

    int y = 110;
    for (int k = 0; k < playersN; k++) {
        Player *p = &players[order[k]];
        char line[96];
        snprintf(line, sizeof line, "%d.  %s%s  -  %d pts", k + 1,
                 p->name[0] ? p->name : "someone", p->isMe ? " (you)" : "", p->score);
        Color col = p->isMe ? C_ACCENT2 : C_TEXT;
        DrawText(line, 320, y, 20, col);

        char words[512] = "";
        int off = 0;
        for (int i = 0; i < p->wordsN && off < (int)sizeof words - 24; i++)
            off += snprintf(words + off, sizeof words - off, "%s%s", i ? ", " : "", p->words[i]);
        if (off >= (int)sizeof words - 24) snprintf(words + off, sizeof words - off, ", ...");
        if (words[0]) DrawText(words, 320, y + 24, 14, C_DIM);
        y += 48;
    }

    if (iAmHost()) {
        if (uiButton((Rectangle){356, 480, 248, 44}, "NEXT ROUND", 1)) sendStart();
    } else {
        drawCentered("waiting for the host...", 494, 16, C_DIM);
    }
}

/* -------------------------------------------------------------------- lobby */
static void doJoin(void) {
    char nm[MAX_NAME_LEN] = "", rm[MAX_ROOM_LEN] = "";
    int a = 0, b = 0;
    for (int i = 0; inputName[i] && a < MAX_NAME_LEN - 1; i++) {
        char ch = inputName[i];
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
            ch == ' ' || ch == '-' || ch == '_' || ch == '.')
            nm[a++] = ch;
    }
    for (int i = 0; inputRoom[i] && b < MAX_ROOM_LEN - 1; i++) {
        char ch = inputRoom[i];
        if (ch >= 'A' && ch <= 'Z') ch += 32;
        if ((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')) rm[b++] = ch;
    }
    if (!nm[0]) {
        setToast("Please enter a name");
        return;
    }
    if (!rm[0]) {
        setToast("Please enter a room code");
        return;
    }
    strncpy(myName, nm, sizeof myName - 1);
    strncpy(room, rm, sizeof room - 1);
    phase = ST_JOINING;
    joinStartedAt = js_now();
    js_join(room, myName);
}

static void handleLobbyInput(void) {
    int c;
    while ((c = GetCharPressed()) > 0) {
        char ch = (char)c;
        if (focusField == 0 && strlen(inputName) < MAX_NAME_LEN - 1 && ch >= 32 && ch < 127) {
            inputName[strlen(inputName) + 1] = 0;
            inputName[strlen(inputName)] = ch;
        } else if (focusField == 1 && strlen(inputRoom) < MAX_ROOM_LEN - 1 &&
                   ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') ||
                    (ch >= '0' && ch <= '9') || ch == '-' || ch == ' ')) {
            inputRoom[strlen(inputRoom) + 1] = 0;
            inputRoom[strlen(inputRoom)] = ch;
        }
    }
    if (IsKeyPressed(KEY_BACKSPACE)) {
        char *s = focusField == 0 ? inputName : inputRoom;
        int l = (int)strlen(s);
        if (l > 0) s[l - 1] = 0;
    }
    if (IsKeyPressed(KEY_ENTER) || IsKeyPressed(KEY_TAB)) {
        if (focusField == 0)
            focusField = 1;
        else
            doJoin();
    }
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        Vector2 m = GetMousePosition();
        Rectangle nameRect = {308, 262, 344, 44};
        Rectangle roomRect = {308, 352, 344, 44};
        if (CheckCollisionPointRec(m, nameRect)) focusField = 0;
        if (CheckCollisionPointRec(m, roomRect)) focusField = 1;
    }
}

static void handlePlayInput(void) {
    if (IsMouseButtonPressed(MOUSE_BUTTON_LEFT)) {
        Vector2 m = GetMousePosition();
        for (int i = 0; i < 16; i++) {
            int r = i / 4, c = i % 4;
            Rectangle rect = {36.0f + c * 91.0f, 110.0f + r * 91.0f, 82, 82};
            if (!CheckCollisionPointRec(m, rect)) continue;
            if (pathLen > 0 && path[pathLen - 1] == i)
                popTile();
            else
                pushTile(i);
            break;
        }
    }
    if (IsKeyPressed(KEY_ENTER)) submitWord();
    if (IsKeyPressed(KEY_BACKSPACE)) popTile();
    if (IsKeyPressed(KEY_ESCAPE)) clearSel();
}

/* ------------------------------------------------------------------- frame */
static void UpdateDrawFrame(void) {
    double now = js_now();

    if (phase == ST_JOINING && now - joinStartedAt > JOIN_TIMEOUT_MS) {
        phase = ST_LOBBY;
        setToast("Join timed out - is the server reachable?");
    }
    if (phase == ST_ROOM || phase == ST_PLAY || phase == ST_RESULTS) {
        if (now - lastHello > HELLO_INTERVAL_MS) {
            lastHello = now;
            sendHello();
        }
        /* The host periodically publishes an authoritative snapshot so that
         * transient connection drops self-heal (lost awards/claims resync). */
        if (phase == ST_PLAY && iAmHost() && now - lastState > STATE_INTERVAL_MS) {
            lastState = now;
            sendState();
        }
        /* keep re-sending an unacknowledged claim until the host answers */
        if (phase == ST_PLAY && pendingWord[0]) {
            if (iAmHost()) {
                /* we took over as host: adjudicate our own pending claim */
                Player *me = playerById(meId);
                if (me && !playerHasWord(me, pendingWord) &&
                    !anyoneHasWord(pendingWord, meId) && dictHas(pendingWord) &&
                    wordOnBoard(pendingWord)) {
                    addWordTo(me, pendingWord);
                    sendAward(pendingWord, meId, scoreForLen((int)strlen(pendingWord)));
                }
                pendingWord[0] = 0;
            } else if (now - pendingSentAt > 5000.0) {
                pendingSentAt = now;
                sendClaim(pendingWord);
            }
        }
        for (int i = playersN - 1; i >= 0; i--) {
            if (!players[i].isMe && now - players[i].lastSeen > PLAYER_TIMEOUT_MS) {
                setToast("%s left", players[i].name[0] ? players[i].name : "A player");
                removePlayerAt(i);
                if (iAmHost()) sendState();
            }
        }
        checkRoundEnd();
    }

    if (phase == ST_LOBBY) handleLobbyInput();
    if (phase == ST_PLAY) handlePlayInput();

    BeginDrawing();
    ClearBackground(C_BG);
    switch (phase) {
    case ST_LOBBY: drawLobby(); break;
    case ST_JOINING: drawJoining(); break;
    case ST_ROOM: drawRoom(); break;
    case ST_PLAY: drawPlay(); break;
    case ST_RESULTS: drawResults(); break;
    }
    drawToast();
    EndDrawing();
}

int main(void) {
    InitWindow(GAME_W, GAME_H, "Boggle");
    SetTargetFPS(60);

    loadDict();

    /* suggest a random room code (player can edit it) */
    SetRandomSeed((unsigned)js_now());
    for (int i = 0; i < 6; i++)
        inputRoom[i] = (char)('A' + GetRandomValue(0, 25));
    inputRoom[6] = 0;
    focusField = 0;

    emscripten_set_main_loop(UpdateDrawFrame, 0, 1);
    return 0;
}
