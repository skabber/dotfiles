// Lightweight HTTP server wrapping defuddle's Node API.
// Used by the NixOS defuddle service module.

const http = require('http');
const path = require('path');

const DEFUDDLE_DIR = process.env.DEFUDDLE_DIR || '/home/jay/Projects/defuddle';
const PORT = parseInt(process.env.DEFUDDLE_PORT || '3002', 10);

// Load defuddle from its build output
const { Defuddle } = require(path.join(DEFUDDLE_DIR, 'dist/node.js'));
const { getInitialUA, fetchPage, extractRawMarkdown, cleanMarkdownContent, BOT_UA } = require(path.join(DEFUDDLE_DIR, 'dist/fetch.js'));
const { countWords } = require(path.join(DEFUDDLE_DIR, 'dist/utils.js'));

function escapeYaml(s) {
  return s.replace(/"/g, '\\"').replace(/\n/g, ' ');
}

function truncateWords(text, maxWords) {
  let words = 0;
  let inWord = false;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    const isCJK = (code >= 0x3040 && code <= 0x309f) || (code >= 0x30a0 && code <= 0x30ff) ||
      (code >= 0x3400 && code <= 0x4dbf) || (code >= 0x4e00 && code <= 0x9fff) ||
      (code >= 0xf900 && code <= 0xfaff) || (code >= 0xac00 && code <= 0xd7af);
    if (isCJK) { words++; inWord = false; }
    else if (code <= 32) { inWord = false; }
    else if (!inWord) { words++; inWord = true; }
    if (words > maxWords) return text.slice(0, i).trimEnd() + '\u2026';
  }
  return text;
}

function formatResponse(result, sourceUrl) {
  const lines = ['---'];
  if (result.title) lines.push(`title: "${escapeYaml(result.title)}"`);
  if (result.author) lines.push(`author: "${escapeYaml(result.author)}"`);
  if (result.site) lines.push(`site: "${escapeYaml(result.site)}"`);
  if (result.published) lines.push(`published: ${result.published}`);
  lines.push(`source: "${sourceUrl}"`);
  if (result.domain) lines.push(`domain: "${result.domain}"`);
  if (result.language) lines.push(`language: "${result.language}"`);
  if (result.description) {
    const desc = countWords(result.description) > 300
      ? truncateWords(result.description, 300)
      : result.description;
    lines.push(`description: "${escapeYaml(desc)}"`);
  }
  if (result.wordCount) lines.push(`word_count: ${result.wordCount}`);
  lines.push('---');
  return lines.join('\n') + '\n\n' + result.content;
}

async function convertToMarkdown(targetUrl, language) {
  const initialUA = getInitialUA(targetUrl);
  const html = await fetchPage(targetUrl, initialUA, language);
  let result = await Defuddle(html, targetUrl, { markdown: true, language });

  // Retry with bot UA if no content (page may be JS-rendered)
  if (result.wordCount === 0 && initialUA !== BOT_UA) {
    try {
      const botHtml = await fetchPage(targetUrl, BOT_UA, language);
      const rawMarkdown = extractRawMarkdown(botHtml);
      if (rawMarkdown) {
        const botResult = await Defuddle(botHtml, targetUrl, { markdown: true, language });
        botResult.content = cleanMarkdownContent(rawMarkdown);
        botResult.wordCount = countWords(botResult.content);
        return botResult;
      }
      const botResult = await Defuddle(botHtml, targetUrl, { markdown: true, language });
      if (botResult.wordCount > 0) return botResult;
    } catch {}
  }

  return result;
}

function jsonResponse(res, data, status = 200) {
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(data));
}

function errorResponse(res, message, status) {
  jsonResponse(res, { error: message }, status);
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const reqPath = url.pathname;

    // CORS preflight
    if (req.method === 'OPTIONS') {
      res.writeHead(204, {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
      return res.end();
    }

    // Health check
    if (reqPath === '/' || reqPath === '/health') {
      return jsonResponse(res, { status: 'ok', service: 'defuddle' });
    }

    // POST /api/parse - parse raw HTML
    if (reqPath === '/api/parse' && req.method === 'POST') {
      const chunks = [];
      for await (const chunk of req) chunks.push(chunk);
      const body = JSON.parse(Buffer.concat(chunks).toString());
      if (!body.html) return errorResponse(res, 'Missing "html" field in request body.', 400);
      const result = await Defuddle(body.html, body.url || '', { markdown: true });
      return jsonResponse(res, result);
    }

    // GET /{url} - convert URL to markdown (catch-all)
    let targetUrl = reqPath.replace(/^\/+/, '');
    targetUrl = decodeURIComponent(targetUrl);
    if (url.search) targetUrl += url.search;
    if (!targetUrl.match(/^https?:\/\//)) targetUrl = 'https://' + targetUrl;

    let parsedTarget;
    try { parsedTarget = new URL(targetUrl); } catch {
      return errorResponse(res, 'Invalid URL.', 400);
    }

    // Block self-referential requests
    if (parsedTarget.hostname === 'localhost' || parsedTarget.hostname === '127.0.0.1') {
      return errorResponse(res, 'Cannot convert this URL.', 400);
    }

    const language = req.headers['accept-language']?.split(',')[0]?.split(';')[0]?.trim() || undefined;
    const result = await convertToMarkdown(targetUrl, language);
    const markdown = formatResponse(result, targetUrl);

    res.writeHead(200, {
      'Content-Type': 'text/markdown; charset=utf-8',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(markdown);
  } catch (err) {
    const message = err instanceof Error ? err.message : 'An unexpected error occurred';
    errorResponse(res, message, 502);
  }
});

server.listen(PORT, () => {
  console.log(`Defuddle server listening on port ${PORT}`);
});
