#!/bin/bash
# Multi-key support + auto failover (Anthropic, OpenAI, Gemini, OpenRouter)
# Pehle add_share.sh aur add_guard.sh chal chuke hone chahiye.
# Usage: repo ke root me:  bash add_keys.sh
set -e

python3 - <<'PY'
import sys

def patch(path, old, new):
    s = open(path, encoding="utf-8").read()
    if new in s:
        return
    if old not in s:
        sys.exit("Patch fail: " + path + " -> " + old[:50])
    open(path, "w", encoding="utf-8").write(s.replace(old, new, 1))

base = "app/src/main/java/com/example/agent/"
svc = base + "ShareService.kt"

# 1) Router + providers, askAnthropic se pehle
patch(svc,
    'private fun ask(key: String, q: String, jpeg: ByteArray): String {',
    r'''private class ApiError(val code: Int, val body: String) :
        RuntimeException("API $code: ${body.take(150)}")

    private class KeyCfg(val raw: String, val provider: String, val key: String, val model: String)

    private val deadKeys = HashSet<String>()

    // Keys comma / space / newline se alag. Optional model: KEY|model-name
    private fun parseKeys(all: String): List<KeyCfg> =
        all.split(",", "\n", " ", ";").map { it.trim() }.filter { it.isNotEmpty() }.map { raw ->
            val parts = raw.split("|", limit = 2)
            val k = parts[0]
            val m = parts.getOrNull(1)?.takeIf { it.isNotBlank() }
            when {
                k.startsWith("sk-ant-") -> KeyCfg(raw, "anthropic", k, m ?: "claude-sonnet-5-5")
                k.startsWith("sk-or-") -> KeyCfg(raw, "openrouter", k, m ?: "openai/gpt-4o-mini")
                k.startsWith("AIza") -> KeyCfg(raw, "gemini", k, m ?: "gemini-2.5-flash")
                else -> KeyCfg(raw, "openai", k, m ?: "gpt-4o-mini")
            }
        }

    private fun ask(keys: String, q: String, jpeg: ByteArray): String {
        val list = parseKeys(keys)
        if (list.isEmpty()) throw RuntimeException("Koi API key nahi mili")
        var lastErr = "Saari keys band ya fail hain"
        for (c in list) {
            if (c.raw in deadKeys) continue
            val tag = c.provider + "..." + c.key.takeLast(4)
            try {
                return when (c.provider) {
                    "anthropic" -> askAnthropic(c.key, q, jpeg, c.model)
                    "gemini" -> askGemini(c.key, q, jpeg, c.model)
                    else -> askOpenAi(c.key, q, jpeg, c.model, c.provider == "openrouter")
                }
            } catch (e: ApiError) {
                val b = e.body.lowercase()
                val dead = e.code in 401..403 ||
                    listOf("credit", "quota", "billing", "balance").any { b.contains(it) }
                if (dead) deadKeys.add(c.raw)
                lastErr = "$tag: ${e.message}"
                log("Key $tag fail (${e.code}), " + (if (dead) "band mani gayi, " else "") + "agli key try")
            } catch (e: Exception) {
                lastErr = "$tag: ${e.message}"
                log("Key $tag error: ${e.message}, agli key try")
            }
        }
        throw RuntimeException(lastErr)
    }

    private fun post(url: String, headers: Map<String, String>, body: JSONObject): String {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod = "POST"
        c.connectTimeout = 15000
        c.readTimeout = 60000
        c.doOutput = true
        c.setRequestProperty("content-type", "application/json")
        headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
        c.outputStream.use { it.write(body.toString().toByteArray()) }
        val code = c.responseCode
        val stream = if (code in 200..299) c.inputStream else c.errorStream
        val txt = stream?.bufferedReader()?.readText() ?: ""
        if (code !in 200..299) throw ApiError(code, txt)
        return txt
    }

    private fun askOpenAi(key: String, q: String, jpeg: ByteArray, model: String, router: Boolean): String {
        val b64 = Base64.encodeToString(jpeg, Base64.NO_WRAP)
        val content = JSONArray()
            .put(JSONObject().put("type", "text").put("text", q))
            .put(JSONObject().put("type", "image_url")
                .put("image_url", JSONObject().put("url", "data:image/jpeg;base64,$b64")))
        val body = JSONObject()
            .put("model", model)
            .put(if (router) "max_tokens" else "max_completion_tokens", 400)
            .put("messages", JSONArray()
                .put(JSONObject().put("role", "system").put("content", systemPrompt))
                .put(JSONObject().put("role", "user").put("content", content)))
        val url = if (router) "https://openrouter.ai/api/v1/chat/completions"
                  else "https://api.openai.com/v1/chat/completions"
        val txt = post(url, mapOf("Authorization" to "Bearer $key"), body)
        return JSONObject(txt).getJSONArray("choices").getJSONObject(0)
            .getJSONObject("message").getString("content")
    }

    private fun askGemini(key: String, q: String, jpeg: ByteArray, model: String): String {
        val parts = JSONArray()
            .put(JSONObject().put("text", q))
            .put(JSONObject().put("inline_data", JSONObject()
                .put("mime_type", "image/jpeg")
                .put("data", Base64.encodeToString(jpeg, Base64.NO_WRAP))))
        val body = JSONObject()
            .put("system_instruction", JSONObject().put("parts",
                JSONArray().put(JSONObject().put("text", systemPrompt))))
            .put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", parts)))
            .put("generationConfig", JSONObject().put("maxOutputTokens", 1024))
        val txt = post(
            "https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent",
            mapOf("x-goog-api-key" to key), body
        )
        return JSONObject(txt).getJSONArray("candidates").getJSONObject(0)
            .getJSONObject("content").getJSONArray("parts").getJSONObject(0).getString("text")
    }

    private fun askAnthropic(key: String, q: String, jpeg: ByteArray, model: String): String {''')

# 2) Anthropic call: model ab parameter se, error ApiError se
patch(svc, '.put("model", "claude-sonnet-5-5")', '.put("model", model)')
patch(svc, 'throw RuntimeException("API $code: ${txt.take(150)}")', 'throw ApiError(code, txt)')

# 3) Start log me keys ka summary (sirf provider + aakhri 4 akshar)
patch(svc,
    'log("Share shuru (${secs}s). Sawal: $q")',
    'log("Share shuru (${secs}s). Keys: ${parseKeys(key).joinToString { it.provider + "..." + it.key.takeLast(4) }}. Sawal: $q")')

# 4) UI hint
patch(base + "MainActivity.kt",
    'hint = "Anthropic API key"',
    'hint = "API keys (comma se alag: sk-ant-..., sk-..., AIza...)"')

print("Multi-key patch lag gaya.")
PY

echo "Done. Ab: git add . && git commit -m keys && git push"
