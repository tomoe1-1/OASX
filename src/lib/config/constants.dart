/// 自更新检查接口：指向本项目的发布库。
///
/// 注意这里刻意不用上游 `AzurTian/OASX` —— OASX 的更新应跟随使用者自己
/// 维护的分支，否则会出现「上游发新版 → 本地提示升级 → 装上去覆盖掉自己的改动」。
const String updateUrlGithub =
    'https://api.github.com/repos/tomoe1-1/OASX/releases/latest';

const String readmeUrlGithub =
    'https://api.github.com/repos/runhey/OnmyojiAutoScript/readme';

/// 发布页兜底链接：接口拿不到 `html_url` 时用它。
const String oasxRelease = "https://github.com/tomoe1-1/OASX/releases";
