/// AI API 供应商预设数据 — 参考 cc-switch 项目(https://github.com/farion1231/cc-switch)
/// 的 Claude 供应商预设整理,Base URL 统一为 OpenAI 兼容端点。
///
/// 预设用途:添加供应商时从预设列表选择,自动填充 Base URL 与默认模型;
/// logo 资源位于 assets/images/provider_logos/ 目录,文件名为 logo 字段 + .png。
class AiProviderPreset {
  const AiProviderPreset({
    required this.name,
    required this.type,
    required this.baseUrl,
    required this.logo,
    this.defaultModel = '',
    this.websiteUrl = '',
  });

  /// 显示名(如 DeepSeek)
  final String name;
  /// 类型标识(唯一,作为 provider_type 存储)
  final String type;
  /// OpenAI 兼容 Base URL
  final String baseUrl;
  /// 默认模型(可为空,创建后可用「获取模型列表」选择)
  final String defaultModel;
  /// logo 资源文件名(不含扩展名)
  final String logo;
  /// 官网地址
  final String websiteUrl;
}

/// 全部预设供应商列表(73 个,参考 cc-switch)。
const List<AiProviderPreset> aiProviderPresets = [
  // 高频预设置顶（表单默认选中 DeepSeek，便于直接使用）
  AiProviderPreset(name: "OpenAI", type: "openai", baseUrl: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", logo: "openai", websiteUrl: "https://platform.openai.com"),
  AiProviderPreset(name: "DeepSeek", type: "deepseek", baseUrl: "https://api.deepseek.com", defaultModel: "deepseek-chat", logo: "deepseek", websiteUrl: "https://platform.deepseek.com"),
  AiProviderPreset(name: "Claude Official", type: "claude", baseUrl: "https://api.anthropic.com/v1", defaultModel: "", logo: "claude", websiteUrl: "https://www.anthropic.com/claude-code"),
  AiProviderPreset(name: "Kimi", type: "kimi", baseUrl: "https://api.moonshot.cn/v1", defaultModel: "kimi-k2.7-code", logo: "kimi", websiteUrl: "https://platform.kimi.com?aff=cc-switch"),
  AiProviderPreset(name: "Kimi For Coding", type: "kimi-2", baseUrl: "https://api.moonshot.cn/v1", defaultModel: "kimi-k2.7-code", logo: "kimi", websiteUrl: "https://www.kimi.com/code/?aff=cc-switch"),
  AiProviderPreset(name: "PackyCode", type: "packycode", baseUrl: "https://www.packyapi.ai/v1", defaultModel: "", logo: "packycode", websiteUrl: "https://www.packyapi.ai"),
  AiProviderPreset(name: "ZetaAPI", type: "zetaapi", baseUrl: "https://api.zetaapi.ai/v1", defaultModel: "", logo: "zetaapi", websiteUrl: "https://zetaapi.ai"),
  AiProviderPreset(name: "APINebula", type: "apinebula", baseUrl: "https://apinebula.ai/v1", defaultModel: "", logo: "apinebula", websiteUrl: "https://apinebula.ai"),
  AiProviderPreset(name: "AICodeMirror", type: "aicodemirror", baseUrl: "https://api.aicodemirror.ai/v1", defaultModel: "", logo: "aicodemirror", websiteUrl: "https://www.aicodemirror.ai"),
  AiProviderPreset(name: "PatewayAI", type: "pateway", baseUrl: "https://api.pateway.ai/v1", defaultModel: "", logo: "pateway", websiteUrl: "https://pateway.ai"),
  AiProviderPreset(name: "FennoAI", type: "fenno", baseUrl: "https://api.fenno.ai/v1", defaultModel: "", logo: "fenno", websiteUrl: "https://api.fenno.ai"),
  AiProviderPreset(name: "RunAPI", type: "runapi", baseUrl: "https://runapi.co/v1", defaultModel: "", logo: "runapi", websiteUrl: "https://runapi.co"),
  AiProviderPreset(name: "Shengsuanyun", type: "shengsuanyun", baseUrl: "https://router.shengsuanyun.com/api", defaultModel: "anthropic/claude-sonnet-5", logo: "shengsuanyun", websiteUrl: "https://www.shengsuanyun.com/?from=CH_4HHXMRYF"),
  AiProviderPreset(name: "AIGoCode", type: "aigocode", baseUrl: "https://api.aigocode.app/v1", defaultModel: "", logo: "aigocode", websiteUrl: "https://aigocode.app"),
  AiProviderPreset(name: "Qiniu", type: "qiniu", baseUrl: "https://api.qnaigc.com/v1", defaultModel: "", logo: "qiniu", websiteUrl: "https://s.qiniu.com/nMvAvy"),
  AiProviderPreset(name: "AICoding", type: "aicoding", baseUrl: "https://api.aicoding.inc/v1", defaultModel: "", logo: "aicoding", websiteUrl: "https://aicoding.inc"),
  AiProviderPreset(name: "SubRouter", type: "subrouter", baseUrl: "https://subrouter.ai/api", defaultModel: "", logo: "subrouter", websiteUrl: "https://subrouter.ai"),
  AiProviderPreset(name: "APIKEY.FUN", type: "apikeyfun", baseUrl: "https://api.apikey.fun/v1", defaultModel: "", logo: "apikeyfun", websiteUrl: "https://apikey.fun"),
  AiProviderPreset(name: "ClaudeAPI", type: "claudeapi", baseUrl: "https://gw.apito.ai/v1", defaultModel: "", logo: "claudeapi", websiteUrl: "https://www.apito.ai"),
  AiProviderPreset(name: "Code0", type: "code0", baseUrl: "https://code0.ai/v1", defaultModel: "", logo: "code0", websiteUrl: "https://code0.ai"),
  AiProviderPreset(name: "TeamoRouter", type: "teamorouter", baseUrl: "https://api.teamorouter.com/v1", defaultModel: "", logo: "teamorouter", websiteUrl: "https://teamorouter.com"),
  AiProviderPreset(name: "ClaudeCN", type: "claudecn", baseUrl: "https://claudecn.top/v1", defaultModel: "", logo: "claudecn", websiteUrl: "https://claudecn.top"),
  AiProviderPreset(name: "火山Agentplan", type: "huoshan", baseUrl: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "ark-code-latest", logo: "huoshan", websiteUrl: "https://www.volcengine.com/activity/codingplan?ac=MMAP8JTTCAQ2&rc=6J6FV5N2&utm_campaign=hw&utm_content=ccswitch&utm_medium=devrel_tool_web&utm_source=OWO&utm_term=ccswitch"),
  AiProviderPreset(name: "BytePlus", type: "byteplus", baseUrl: "https://ark.ap-southeast.bytepluses.com/api/v3", defaultModel: "ark-code-latest", logo: "byteplus", websiteUrl: "https://www.byteplus.com/en/product/modelark?utm_campaign=hw&utm_content=ccswitch&utm_medium=devrel_tool_web&utm_source=OWO&utm_term=ccswitch"),
  AiProviderPreset(name: "DouBaoSeed", type: "doubao", baseUrl: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-seed-2-1-pro-260628", logo: "doubao", websiteUrl: "https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey?apikey=%7B%7D&utm_campaign=hw&utm_content=ccswitch&utm_medium=devrel_tool_web&utm_source=OWO&utm_term=ccswitch"),
  AiProviderPreset(name: "SiliconFlow", type: "siliconflow", baseUrl: "https://api.siliconflow.cn/v1", defaultModel: "Pro/MiniMaxAI/MiniMax-M2.7", logo: "siliconflow", websiteUrl: "https://siliconflow.cn"),
  AiProviderPreset(name: "SiliconFlow en", type: "siliconflow-2", baseUrl: "https://api.siliconflow.com/v1", defaultModel: "MiniMaxAI/MiniMax-M2.7", logo: "siliconflow", websiteUrl: "https://siliconflow.com"),
  AiProviderPreset(name: "A6API", type: "a6api", baseUrl: "https://api.a6api.com/v1", defaultModel: "", logo: "a6api", websiteUrl: "https://www.a6api.com"),
  AiProviderPreset(name: "AtlasCloud", type: "atlascloud", baseUrl: "https://api.atlascloud.ai/v1", defaultModel: "zai-org/glm-5.1", logo: "atlascloud", websiteUrl: "https://www.atlascloud.ai/console/coding-plan"),
  AiProviderPreset(name: "Compshare", type: "ucloud", baseUrl: "https://api.modelverse.cn/v1", defaultModel: "", logo: "ucloud", websiteUrl: "https://www.compshare.cn"),
  AiProviderPreset(name: "Compshare Coding Plan", type: "ucloud-2", baseUrl: "https://cp.compshare.cn/v1", defaultModel: "", logo: "ucloud", websiteUrl: "https://www.compshare.cn"),
  AiProviderPreset(name: "CCSub", type: "ccsub", baseUrl: "https://www.ccsub.net/v1", defaultModel: "", logo: "ccsub", websiteUrl: "https://www.ccsub.net"),
  AiProviderPreset(name: "SSSAiCode", type: "sssaicode", baseUrl: "https://node-hk.sssaicodeapi.com/api", defaultModel: "", logo: "sssaicode", websiteUrl: "https://sssaicodeapi.com"),
  AiProviderPreset(name: "Micu", type: "micu", baseUrl: "https://www.micuapi.ai/v1", defaultModel: "", logo: "micu", websiteUrl: "https://www.micuapi.ai"),
  AiProviderPreset(name: "RightCode", type: "rc", baseUrl: "https://www.rightapi.ai/v1", defaultModel: "", logo: "rc", websiteUrl: "https://www.rightapi.ai"),
  AiProviderPreset(name: "ETok.ai", type: "etok", baseUrl: "https://api.etok.ai/v1", defaultModel: "", logo: "etok", websiteUrl: "https://etok.ai"),
  AiProviderPreset(name: "Cubence", type: "cubence", baseUrl: "https://api.cubence.com/v1", defaultModel: "", logo: "cubence", websiteUrl: "https://cubence.com"),
  AiProviderPreset(name: "CrazyRouter", type: "crazyrouter", baseUrl: "https://cn.crazyrouter.com/v1", defaultModel: "", logo: "crazyrouter", websiteUrl: "https://www.crazyrouter.com"),
  AiProviderPreset(name: "DMXAPI", type: "dmxapi", baseUrl: "https://www.dmxapi.cn/v1", defaultModel: "", logo: "openai", websiteUrl: "https://www.dmxapi.cn"),
  AiProviderPreset(name: "SudoCode.chat", type: "sudocode", baseUrl: "https://api.sudocode.chat/v1", defaultModel: "", logo: "sudocode", websiteUrl: "https://sudocode.chat"),
  AiProviderPreset(name: "SudoCode.us", type: "sudocode-us", baseUrl: "https://sudocode.us/v1", defaultModel: "", logo: "sudocode-us", websiteUrl: "https://sudocode.us"),
  AiProviderPreset(name: "Amux", type: "amux", baseUrl: "https://api.amux.ai/v1", defaultModel: "", logo: "amux", websiteUrl: "https://amux.ai"),
  AiProviderPreset(name: "Gemini Native", type: "gemini", baseUrl: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-3.6-flash", logo: "gemini", websiteUrl: "https://ai.google.dev/gemini-api"),
  AiProviderPreset(name: "OpenCode Go", type: "opencode", baseUrl: "https://opencode.ai/zen/go/v1", defaultModel: "deepseek-v4-flash", logo: "opencode", websiteUrl: "https://opencode.ai/go"),
  AiProviderPreset(name: "Zhipu GLM", type: "zhipu", baseUrl: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-5.1", logo: "zhipu", websiteUrl: "https://open.bigmodel.cn"),
  AiProviderPreset(name: "Zhipu GLM en", type: "zhipu-2", baseUrl: "https://api.z.ai/api/paas/v4", defaultModel: "glm-5.1", logo: "zhipu", websiteUrl: "https://z.ai"),
  AiProviderPreset(name: "Baidu Qianfan Coding Plan", type: "baidu", baseUrl: "https://qianfan.baidubce.com/v2", defaultModel: "qianfan-code-latest", logo: "baidu", websiteUrl: "https://cloud.baidu.com/product/qianfan_modelbuilder"),
  AiProviderPreset(name: "Bailian", type: "bailian", baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "", logo: "bailian", websiteUrl: "https://bailian.console.aliyun.com"),
  AiProviderPreset(name: "Bailian For Coding", type: "bailian-2", baseUrl: "https://coding.dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "", logo: "bailian", websiteUrl: "https://bailian.console.aliyun.com"),
  AiProviderPreset(name: "StepFun", type: "stepfun", baseUrl: "https://api.stepfun.com/v1", defaultModel: "step-3.5-flash-2603", logo: "stepfun", websiteUrl: "https://platform.stepfun.com/step-plan"),
  AiProviderPreset(name: "StepFun en", type: "stepfun-2", baseUrl: "https://api.stepfun.ai/v1", defaultModel: "step-3.5-flash-2603", logo: "stepfun", websiteUrl: "https://platform.stepfun.ai/step-plan"),
  AiProviderPreset(name: "ModelScope", type: "modelscope", baseUrl: "https://api-inference.modelscope.cn/v1", defaultModel: "ZhipuAI/GLM-5.1", logo: "modelscope", websiteUrl: "https://modelscope.cn"),
  AiProviderPreset(name: "KAT-Coder", type: "catcoder", baseUrl: "https://api.kat-coder.com/v1", defaultModel: "", logo: "catcoder", websiteUrl: "https://console.streamlake.ai"),
  AiProviderPreset(name: "Longcat", type: "longcat", baseUrl: "https://api.longcat.chat/v1", defaultModel: "LongCat-2.0", logo: "longcat", websiteUrl: "https://longcat.chat/platform"),
  AiProviderPreset(name: "MiniMax", type: "minimax", baseUrl: "https://api.minimaxi.com/v1", defaultModel: "MiniMax-M2.7", logo: "minimax", websiteUrl: "https://platform.minimaxi.com"),
  AiProviderPreset(name: "MiniMax en", type: "minimax-2", baseUrl: "https://api.minimax.io/v1", defaultModel: "MiniMax-M2.7", logo: "minimax", websiteUrl: "https://platform.minimax.io"),
  AiProviderPreset(name: "BaiLing", type: "bailian-3", baseUrl: "https://api.tbox.cn/api/v1", defaultModel: "Ling-2.5-1T", logo: "bailian", websiteUrl: "https://alipaytbox.yuque.com/sxs0ba/ling/get_started"),
  AiProviderPreset(name: "AiHubMix", type: "aihubmix", baseUrl: "https://aihubmix.com/v1", defaultModel: "", logo: "aihubmix", websiteUrl: "https://aihubmix.com"),
  AiProviderPreset(name: "CherryIN", type: "cherryin", baseUrl: "https://open.cherryin.net/v1", defaultModel: "anthropic/claude-sonnet-5", logo: "cherryin", websiteUrl: "https://open.cherryin.ai"),
  AiProviderPreset(name: "RelaxyCode", type: "relaxcode", baseUrl: "https://www.relaxycode.com/v1", defaultModel: "", logo: "relaxcode", websiteUrl: "https://www.relaxycode.com"),
  AiProviderPreset(name: "E-FlowCode", type: "eflowcode", baseUrl: "https://e-flowcode.cc/v1", defaultModel: "", logo: "eflowcode", websiteUrl: "https://e-flowcode.cc"),
  AiProviderPreset(name: "OpenRouter", type: "openrouter", baseUrl: "https://openrouter.ai/api/v1", defaultModel: "anthropic/claude-sonnet-5", logo: "openrouter", websiteUrl: "https://openrouter.ai"),
  AiProviderPreset(name: "TheRouter", type: "subrouter-2", baseUrl: "https://api.therouter.ai/v1", defaultModel: "anthropic/claude-sonnet-5", logo: "subrouter", websiteUrl: "https://therouter.ai"),
  AiProviderPreset(name: "Novita AI", type: "novita", baseUrl: "https://api.novita.ai/v3/openai", defaultModel: "zai-org/glm-5.1", logo: "novita", websiteUrl: "https://novita.ai"),
  AiProviderPreset(name: "GitHub Copilot", type: "github", baseUrl: "https://api.githubcopilot.com/v1", defaultModel: "claude-sonnet-5", logo: "github", websiteUrl: "https://github.com/features/copilot"),
  AiProviderPreset(name: "Codex", type: "codex", baseUrl: "https://chatgpt.com/backend-api/codex/v1", defaultModel: "gpt-5.6-sol", logo: "openai", websiteUrl: "https://openai.com/chatgpt/pricing"),
  AiProviderPreset(name: "xAI (Grok)", type: "xai", baseUrl: "https://api.x.ai/v1", defaultModel: "grok-4.5", logo: "xai", websiteUrl: "https://x.ai/grok"),
  AiProviderPreset(name: "Nvidia", type: "nvidia", baseUrl: "https://integrate.api.nvidia.com/v1", defaultModel: "moonshotai/kimi-k2.5", logo: "nvidia", websiteUrl: "https://build.nvidia.com"),
  AiProviderPreset(name: "PIPELLM", type: "pipellm", baseUrl: "https://cc-api.pipellm.ai/v1", defaultModel: "claude-opus-5", logo: "pipellm", websiteUrl: "https://code.pipellm.ai"),
  AiProviderPreset(name: "Xiaomi MiMo", type: "xiaomimimo", baseUrl: "https://api.xiaomimimo.com/v1", defaultModel: "mimo-v2.5-pro", logo: "xiaomimimo", websiteUrl: "https://platform.xiaomimimo.com"),
  AiProviderPreset(name: "Xiaomi MiMo Token Plan (China)", type: "xiaomimimo-2", baseUrl: "https://token-plan-cn.xiaomimimo.com/v1", defaultModel: "mimo-v2.5-pro", logo: "xiaomimimo", websiteUrl: "https://platform.xiaomimimo.com/#/token-plan"),
  AiProviderPreset(name: "AWS Bedrock (AKSK)", type: "aws", baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com", defaultModel: "", logo: "aws", websiteUrl: "https://aws.amazon.com/bedrock/"),
  AiProviderPreset(name: "AWS Bedrock (API Key)", type: "aws-2", baseUrl: "https://bedrock-runtime.us-east-1.amazonaws.com", defaultModel: "", logo: "aws", websiteUrl: "https://aws.amazon.com/bedrock/"),
  AiProviderPreset(name: "PPIO", type: "ppio", baseUrl: "https://api.ppio.com/v1", defaultModel: "deepseek/deepseek-v4-flash-0", logo: "ppio", websiteUrl: "https://ppio.com"),
];
