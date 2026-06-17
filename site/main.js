const modules = [
  {
    id: "memory",
    label: "01",
    title: "长期陪伴型 AI 记忆机制",
    summary:
      "对话轮次变多后，不能把全量历史塞进提示词。更稳的做法是分层管理记忆：近期上下文保连贯，结构化画像保事实，长期情景记忆保语义背景。",
    points: [
      ["短期记忆", "保留近期多轮原始对话，直接参与 prompt，解决当前对话连贯性。"],
      ["实体画像记忆", "抽取用户身份、偏好、经历、目标等稳定事实，用结构化数据精准检索。"],
      ["长期情景记忆", "把闲聊、感悟、项目背景等非事实内容切片向量化，用语义召回。"],
      ["异步更新", "AI 先响应用户，后台做事实抽取、冲突合并、入库和遗忘更新。"]
    ],
    answer:
      "我不会把全部历史直接塞进 prompt，而是做分层记忆。近期几轮对话作为短期记忆直接拼接；用户偏好、身份、经历这类事实抽取成结构化画像，用数据库精准查询；感悟、闲聊、项目背景这类非结构化内容切片后向量化，放入向量库做语义召回。生成回答时，把系统提示词、画像事实、召回片段和近期对话组合起来。记忆更新放到异步后台做，包括事实抽取、入库、冲突合并和遗忘更新。"
  },
  {
    id: "rag",
    label: "02",
    title: "RAG 向量数据全流程工程化",
    summary:
      "RAG 的效果不只取决于大模型，数据质量决定下限，工程链路决定上限。完整链路包括解析清洗、元数据、语义切片、向量化、索引、检索、重排和评估。",
    points: [
      ["预处理", "统一 PDF、网页、文档格式，清洗乱码、广告、页眉页脚，并提取权限、时间、来源等元数据。"],
      ["语义切片", "按标题、段落、句子边界切分，保留 10% 到 20% 重叠，避免破坏语义。"],
      ["父子块架构", "子块用于精准检索，父块用于返回上下文，兼顾召回精度和完整性。"],
      ["闭环优化", "用向量加关键词混合检索，搭配 reranker，并评估召回率、幻觉率、延迟和成本。"]
    ],
    answer:
      "我会把 RAG 看成数据工程问题，而不是只接一个向量库。首先对 PDF、网页、文档做解析和清洗，统一格式，去掉噪音，并提取时间、作者、权限等元数据。切片上避免固定长度硬切，优先按语义结构切分，并设置 10% 到 20% 的重叠。为了兼顾精度和上下文完整性，可以用子块检索、父块返回。向量化阶段通用场景用成熟 embedding 模型，专业领域需要评估或微调。向量库在千万级数据下可以用 HNSW 索引，同时做批量入库和元数据过滤。检索时采用向量加关键词的混合检索，再用 reranker 重排。"
  },
  {
    id: "long-rag",
    label: "03",
    title: "长上下文模型与 RAG 的关系",
    summary:
      "长上下文不会简单取代 RAG。RAG 负责从海量数据中做粗召回，解决信息广度；长上下文模型负责精读候选材料，解决信息深度。",
    points: [
      ["成本", "全量长文本输入会显著增加 token 成本，RAG 能把输入控制在有效片段内。"],
      ["延迟", "上下文越长响应越慢，线上系统更需要先召回再生成。"],
      ["中间迷失", "过长上下文会让模型忽略中间关键信息，RAG 可以先去粗取精。"],
      ["数据治理", "RAG 检索阶段可以处理权限、版本、来源和引用，长上下文本身不解决治理问题。"]
    ],
    answer:
      "我认为长上下文不会直接取代 RAG，而是会和 RAG 融合。RAG 的价值是从海量外部知识中做低成本、低延迟、可权限控制的粗召回，解决信息广度问题；长上下文模型适合对召回后的高质量材料做深度阅读和跨文档推理，解决信息深度问题。即使模型支持很长上下文，全量输入仍然有 token 成本、响应延迟和中间迷失问题，而且企业知识库还需要权限、版本和引用治理。因此更合理的趋势是 Long RAG。"
  },
  {
    id: "transformer",
    label: "04",
    title: "Transformer 超长上下文瓶颈与优化",
    summary:
      "Transformer 长文本问题的本质是平方级注意力计算、KV Cache 显存压力、显存 IO 瓶颈和位置编码外推问题，需要多层优化组合解决。",
    points: [
      ["O(n^2) 注意力", "标准自注意力需要每个 token 与其他 token 交互，长度增加会导致计算量平方级增长。"],
      ["KV Cache", "推理时需要保存历史 Key 和 Value，长上下文和高并发会快速吃满显存。"],
      ["FlashAttention", "通过算子融合和分块计算减少显存读写，缓解注意力计算中的 IO 瓶颈。"],
      ["GQA / PagedAttention / 位置编码", "GQA 减少 KV Cache，PagedAttention 提升显存利用率，RoPE Scaling 和 ALiBi 改善长度外推。"]
    ],
    answer:
      "Transformer 处理超长上下文主要有三个瓶颈。第一是自注意力 O(n^2) 的计算复杂度，长度增加会导致计算量平方级上涨。第二是推理阶段 KV Cache 带来的显存和带宽压力，高并发长文本场景下显存搬运可能比计算更慢。第三是位置编码外推性，模型如果主要在短上下文训练，直接扩到超长文本会导致位置信息泛化变差。优化上，FlashAttention 减少显存 IO；GQA 减少 KV Cache；PagedAttention 用分页方式管理 KV Cache；RoPE Scaling、ALiBi 等方法提升长文本适配能力。"
  }
];

const list = document.querySelector("#module-list");
const detail = document.querySelector("#module-detail");
const search = document.querySelector("#search");

let selectedId = modules[0].id;

function renderList(filter = "") {
  const normalized = filter.trim().toLowerCase();
  const visibleModules = modules.filter((module) => {
    const content = `${module.title} ${module.summary} ${module.points.flat().join(" ")} ${module.answer}`.toLowerCase();
    return content.includes(normalized);
  });

  list.innerHTML = visibleModules
    .map(
      (module) => `
        <button class="module-button ${module.id === selectedId ? "active" : ""}" data-id="${module.id}">
          <span>${module.label}</span>
          ${module.title}
        </button>
      `
    )
    .join("");

  if (!visibleModules.some((module) => module.id === selectedId) && visibleModules[0]) {
    selectedId = visibleModules[0].id;
  }
  if (visibleModules.length === 0) {
    detail.innerHTML = '<p class="module-summary">没有匹配的知识点。换个关键词试试，比如 RAG、记忆、KV Cache。</p>';
    return;
  }

  renderDetail();
}

function renderDetail() {
  const module = modules.find((item) => item.id === selectedId) || modules[0];
  detail.innerHTML = `
    <span class="module-kicker">${module.label}</span>
    <h3 id="${module.id}">${module.title}</h3>
    <p class="module-summary">${module.summary}</p>
    <div class="point-grid">
      ${module.points
        .map(
          ([title, text]) => `
            <section class="point">
              <strong>${title}</strong>
              <p>${text}</p>
            </section>
          `
        )
        .join("")}
    </div>
    <div class="answer-box">
      <strong>面试回答模板：</strong>
      ${module.answer}
    </div>
  `;
}

list.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-id]");
  if (!button) return;
  selectedId = button.dataset.id;
  renderList(search.value);
});

search.addEventListener("input", () => renderList(search.value));

function drawKnowledgeCanvas() {
  const canvas = document.querySelector("#knowledge-canvas");
  const context = canvas.getContext("2d");
  const pixelRatio = window.devicePixelRatio || 1;
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;

  canvas.width = width * pixelRatio;
  canvas.height = height * pixelRatio;
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
  context.clearRect(0, 0, width, height);

  const colors = ["#c44536", "#1f7a63", "#e0a935", "#2f63a3", "#1d1d1f"];
  const nodes = Array.from({ length: 42 }, (_, index) => ({
    x: (width * ((index * 37) % 100)) / 100,
    y: (height * ((index * 53) % 100)) / 100,
    r: 2 + (index % 4),
    color: colors[index % colors.length]
  }));

  context.lineWidth = 1;
  nodes.forEach((node, index) => {
    nodes.slice(index + 1).forEach((other) => {
      const distance = Math.hypot(node.x - other.x, node.y - other.y);
      if (distance < 190) {
        context.strokeStyle = `rgba(29, 29, 31, ${0.18 - distance / 1400})`;
        context.beginPath();
        context.moveTo(node.x, node.y);
        context.lineTo(other.x, other.y);
        context.stroke();
      }
    });
  });

  nodes.forEach((node) => {
    context.fillStyle = node.color;
    context.beginPath();
    context.arc(node.x, node.y, node.r, 0, Math.PI * 2);
    context.fill();
  });
}

renderList();
drawKnowledgeCanvas();
window.addEventListener("resize", drawKnowledgeCanvas);
