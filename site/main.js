const modules = [
  {
    id: "memory",
    title: "记忆机制",
    prompt: "长期陪伴型 AI 的记忆机制怎么设计？",
    summary: "短期记忆、结构化画像、长期情景记忆、异步更新和遗忘机制。"
  },
  {
    id: "rag",
    title: "RAG 工程",
    prompt: "RAG 向量数据工程链路是什么？",
    summary: "解析清洗、语义切片、向量化、索引、混合检索和重排。"
  },
  {
    id: "long-rag",
    title: "Long RAG",
    prompt: "长上下文模型会取代 RAG 吗？",
    summary: "RAG 做筛选，长上下文做精读，两者互补。"
  },
  {
    id: "transformer",
    title: "长上下文优化",
    prompt: "Transformer 处理超长上下文有哪些瓶颈？",
    summary: "O(n^2)、KV Cache、FlashAttention、GQA、PagedAttention、位置编码。"
  }
];

const knowledge = {
  memory:
    "长期陪伴型 AI 不应把所有历史塞进 prompt。更稳的方案是分层记忆：近期多轮对话作为短期记忆；用户身份、偏好、目标等事实抽取成结构化画像；闲聊、项目背景、感悟等内容作为长期情景记忆。生成时按需召回，更新时用异步任务做事实抽取、冲突合并和遗忘。",
  rag:
    "RAG 要按数据工程链路来设计：先解析 PDF、网页、Markdown 等文档并清洗噪音，再提取元数据；切片时按标题、段落和语义边界切分，保留重叠；向量化后写入向量库；检索阶段用向量 + 关键词混合检索，再用 reranker 重排；最后用召回率、引用准确性、幻觉率、延迟和成本做闭环评估。",
  "long-rag":
    "长上下文不会简单取代 RAG。RAG 的价值是从海量资料里低成本、低延迟、可权限控制地筛选相关内容；长上下文模型适合对筛选后的高质量材料精读和跨文档推理。未来更现实的是 Long RAG：先召回，再精读。",
  transformer:
    "Transformer 处理超长上下文的核心瓶颈是自注意力 O(n^2) 计算复杂度、KV Cache 显存与带宽压力、显存 IO 瓶颈以及位置编码外推能力。常见优化包括 FlashAttention、GQA、PagedAttention、RoPE Scaling、ALiBi 等。"
};

const db = {
  open() {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open("agent-interview-local-db", 1);
      request.onupgradeneeded = () => {
        const database = request.result;
        if (!database.objectStoreNames.contains("messages")) {
          database.createObjectStore("messages", { keyPath: "id", autoIncrement: true });
        }
        if (!database.objectStoreNames.contains("facts")) {
          database.createObjectStore("facts", { keyPath: "id", autoIncrement: true });
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  },
  async all(storeName) {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const request = database.transaction(storeName, "readonly").objectStore(storeName).getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  },
  async add(storeName, value) {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const request = database.transaction(storeName, "readwrite").objectStore(storeName).add(value);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
  },
  async clear(storeName) {
    const database = await this.open();
    return new Promise((resolve, reject) => {
      const request = database.transaction(storeName, "readwrite").objectStore(storeName).clear();
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
  }
};

const messagesEl = document.querySelector("#messages");
const form = document.querySelector("#chat-form");
const input = document.querySelector("#message-input");
const moduleList = document.querySelector("#module-list");
const clearButton = document.querySelector("#clear-chat");
const settingsButton = document.querySelector("#settings-button");
const settingsDialog = document.querySelector("#settings-dialog");
const modelBaseInput = document.querySelector("#model-base-input");
const modelNameInput = document.querySelector("#model-name-input");
const apiKeyInput = document.querySelector("#api-key-input");
const profileFactInput = document.querySelector("#profile-fact-input");
const saveFactButton = document.querySelector("#save-fact-button");
const saveSettingsButton = document.querySelector("#save-settings-button");
const factList = document.querySelector("#fact-list");
const installButton = document.querySelector("#install-button");
const statusDot = document.querySelector("#model-status-dot");
const statusTitle = document.querySelector("#model-status-title");
const statusCopy = document.querySelector("#model-status-copy");

let deferredInstallPrompt = null;
let messages = [];
let facts = [];
let settings = loadSettings();

function loadSettings() {
  return {
    baseUrl: localStorage.getItem("agent-model-base-url") || "https://api.openai.com/v1",
    model: localStorage.getItem("agent-model-name") || "gpt-4.1-mini",
    apiKey: localStorage.getItem("agent-model-api-key") || ""
  };
}

function saveSettings() {
  localStorage.setItem("agent-model-base-url", settings.baseUrl);
  localStorage.setItem("agent-model-name", settings.model);
  localStorage.setItem("agent-model-api-key", settings.apiKey);
}

async function init() {
  messages = await db.all("messages");
  facts = await db.all("facts");
  if (messages.length === 0) {
    await addMessage({
      role: "assistant",
      content:
        "你好，我是 Agent 面试机器人。当前不用后端，记忆保存在手机本地。配置模型 API Key 后，我会直连大模型；不配置时，我用内置知识库给你练习。"
    });
    messages = await db.all("messages");
  }
  renderModules();
  renderStatus();
  renderMessages();
}

async function addMessage(message) {
  await db.add("messages", { ...message, createdAt: Date.now() });
}

function renderModules() {
  moduleList.innerHTML = modules
    .map(
      (module) => `
        <button class="module-card" data-question="${module.prompt}" type="button">
          <strong>${module.title}</strong>
          <span>${module.summary}</span>
        </button>
      `
    )
    .join("");
}

function renderStatus() {
  const connected = Boolean(settings.apiKey);
  statusDot.className = `status-dot ${connected ? "connected" : "demo"}`;
  statusTitle.textContent = connected ? "直连模型" : "本地 Demo";
  statusCopy.textContent = connected ? `${settings.model} · ${settings.baseUrl}` : "未配置模型，使用内置知识回答。";
}

function renderMessages() {
  messagesEl.innerHTML = messages
    .map(
      (message) => `
        <article class="message ${message.role}">
          <div class="bubble">${escapeHtml(message.content).replace(/\n/g, "<br />")}</div>
        </article>
      `
    )
    .join("");
  messagesEl.scrollTop = messagesEl.scrollHeight;
}

function renderFacts() {
  factList.innerHTML = facts.length
    ? facts.map((fact) => `<span>${escapeHtml(fact.content)}</span>`).join("")
    : "<small>暂无本地画像事实。</small>";
}

async function sendMessage(question) {
  const trimmed = question.trim();
  if (!trimmed) return;

  await addMessage({ role: "user", content: trimmed });
  await addMessage({ role: "assistant", content: "正在思考..." });
  messages = await db.all("messages");
  renderMessages();

  const answer = settings.apiKey ? await callModel(trimmed).catch((error) => fallbackAnswer(trimmed, error)) : buildDemoAnswer(trimmed);
  const last = messages[messages.length - 1];
  await db.clear("messages");
  const updated = [...messages.slice(0, -1), { ...last, content: answer }];
  for (const message of updated.slice(-40)) {
    await addMessage({ role: message.role, content: message.content });
  }
  messages = await db.all("messages");
  renderMessages();
}

async function callModel(message) {
  const systemPrompt = buildSystemPrompt();
  const response = await fetch(`${settings.baseUrl.replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${settings.apiKey}`
    },
    body: JSON.stringify({
      model: settings.model,
      messages: [
        { role: "system", content: systemPrompt },
        ...messages.slice(-8).map((item) => ({ role: item.role, content: item.content })),
        { role: "user", content: message }
      ]
    })
  });
  if (!response.ok) {
    throw new Error(`模型接口返回 HTTP ${response.status}`);
  }
  const data = await response.json();
  return data.choices?.[0]?.message?.content || "模型没有返回内容。";
}

function buildSystemPrompt() {
  const factText = facts.map((fact) => `- ${fact.content}`).join("\n") || "无";
  const knowledgeText = Object.entries(knowledge)
    .map(([key, value]) => `[${key}]\n${value}`)
    .join("\n\n");
  return `你是一个大模型 Agent 算法面试陪练。请用中文回答，结构清晰，优先给出面试可表达的答案。

本地用户画像：
${factText}

内置知识库：
${knowledgeText}

要求：
1. 先讲核心矛盾。
2. 再拆系统结构。
3. 最后补工程取舍。
4. 不要声称你做了 RAG 检索；当前版本只使用内置知识和本地记忆。`;
}

function fallbackAnswer(message, error) {
  return `模型调用失败：${error.message}\n\n已切换到本地 Demo：\n${buildDemoAnswer(message)}`;
}

function buildDemoAnswer(message) {
  const key = pickKnowledgeKey(message);
  const factHint = facts.length ? `\n\n结合你的本地画像：${facts.map((fact) => fact.content).join("；")}` : "";
  return `${knowledge[key]}${factHint}\n\n面试表达建议：先讲核心矛盾，再拆系统结构，最后补工程取舍。`;
}

function pickKnowledgeKey(message) {
  const lower = message.toLowerCase();
  if (lower.includes("transformer") || lower.includes("kv") || message.includes("长上下文优化")) return "transformer";
  if (lower.includes("long") || message.includes("取代") || message.includes("长上下文")) return "long-rag";
  if (lower.includes("rag") || message.includes("向量") || message.includes("检索")) return "rag";
  if (message.includes("记忆") || message.includes("画像")) return "memory";
  return "rag";
}

function escapeHtml(text) {
  return text.replace(/[&<>"']/g, (char) => {
    const map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#039;" };
    return map[char];
  });
}

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const value = input.value;
  input.value = "";
  input.style.height = "auto";
  sendMessage(value);
});

input.addEventListener("input", () => {
  input.style.height = "auto";
  input.style.height = `${Math.min(input.scrollHeight, 140)}px`;
});

document.querySelectorAll("[data-question]").forEach((button) => {
  button.addEventListener("click", () => sendMessage(button.dataset.question));
});

moduleList.addEventListener("click", (event) => {
  const button = event.target.closest("[data-question]");
  if (button) sendMessage(button.dataset.question);
});

clearButton.addEventListener("click", async () => {
  await db.clear("messages");
  await addMessage({ role: "assistant", content: "对话已清空。继续问我一个 Agent 面试题吧。" });
  messages = await db.all("messages");
  renderMessages();
});

settingsButton.addEventListener("click", () => {
  modelBaseInput.value = settings.baseUrl;
  modelNameInput.value = settings.model;
  apiKeyInput.value = settings.apiKey;
  profileFactInput.value = "";
  renderFacts();
  settingsDialog.showModal();
});

saveSettingsButton.addEventListener("click", () => {
  settings.baseUrl = modelBaseInput.value.trim() || "https://api.openai.com/v1";
  settings.model = modelNameInput.value.trim() || "gpt-4.1-mini";
  settings.apiKey = apiKeyInput.value.trim();
  saveSettings();
  renderStatus();
  settingsDialog.close();
});

saveFactButton.addEventListener("click", async () => {
  const content = profileFactInput.value.trim();
  if (!content) return;
  await db.add("facts", { content, createdAt: Date.now() });
  facts = await db.all("facts");
  profileFactInput.value = "";
  renderFacts();
});

window.addEventListener("beforeinstallprompt", (event) => {
  event.preventDefault();
  deferredInstallPrompt = event;
  installButton.hidden = false;
});

installButton.addEventListener("click", async () => {
  if (!deferredInstallPrompt) return;
  deferredInstallPrompt.prompt();
  await deferredInstallPrompt.userChoice;
  deferredInstallPrompt = null;
  installButton.hidden = true;
});

if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("./sw.js");
  });
}

init();

