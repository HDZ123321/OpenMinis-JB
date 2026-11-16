const fs = require('fs');

const xcPath = 'src/ios/Localizable.xcstrings';
const j = JSON.parse(fs.readFileSync(xcPath, 'utf8'));

// key -> [zh-Hans, zh-Hant]
const translations = {
  'Jailbreak': ['破限', '破限'],
  'Content Layer': ['内容层', '內容層'],
  'Enable Jailbreak Layer': ['启用破限层', '啟用破限層'],
  'Appends a content-instruction block to the end of every system prompt, and retries once per configured attempt when the reply reads as a refusal. Nothing here changes the network layer or the model you selected.':
    ['在每次系统提示词末尾追加一段内容指令；回复被判定为拒绝时，按设定次数重试。这里不改变任何网络层行为，也不影响你选的模型。',
     '在每次系統提示詞末尾追加一段內容指令；回覆被判為拒絕時，按設定次數重試。這裡不改變任何網路層行為，也不影響你選的模型。'],
  'Family': ['家族', '家族'],
  'Auto (detect per message)': ['自动（按消息判定）', '自動（按訊息判定）'],
  'Technical / reverse engineering': ['技术 / 逆向', '技術 / 逆向'],
  'Creative writing': ['创作', '創作'],
  'General': ['通用', '通用'],
  'Picks a family from the keywords in your latest message.': ['按你最新一条消息里的关键词挑家族。', '按你最新一則訊息裡的關鍵詞挑家族。'],
  'Framing as internal engineering documentation.': ['以内部工程文档的形式处理。', '以內部工程文件的形式處理。'],
  'Framing as adult fiction authoring.': ['以成人向小说写作的形式处理。', '以成人向小說寫作的形式處理。'],
  'No domain framing — the generic override only.': ['不做领域包装，只用通用覆盖。', '不做領域包裝，只用通用覆蓋。'],
  'Template': ['模板', '模板'],
  'Follow the ladder instead': ['改为跟随阶梯', '改為跟隨階梯'],
  'Ladder level': ['阶梯档位', '階梯檔位'],
  'Level 1 is the softest framing, level 5 the most explicit. A refusal retry steps one level up, up to the retry limit below.':
    ['档位 1 最轻，档位 5 最直接。拒绝重试会往上走一档，直到下面设的重试上限。',
     '檔位 1 最輕，檔位 5 最直接。拒絕重試會往上走一檔，直到下面設的重試上限。'],
  'Shaping': ['塑形', '塑形'],
  'Ask for a fixed opening line': ['要求固定开场白', '要求固定開場白'],
  'Append reinforcement constraint': ['追加补充约束', '追加補充約束'],
  'The fixed opening line pushes the first token past the refusal pattern models fall into when a request opens cold. The reinforcement constraint restates that a refusal counts as a formatting error.':
    ['固定开场白让第一句直接进入正文，避开冷启动时的拒绝惯性。补充约束重申：拒绝属于格式错误。',
     '固定開場白讓第一句直接進入正文，避開冷啟動時的拒絕慣性。補充約束重申：拒絕屬於格式錯誤。'],
  'Retry': ['重试', '重試'],
  'Retry on refusal': ['拒绝时重试', '拒絕時重試'],
  'Max retries per turn': ['每轮最大重试次数', '每輪最大重試次數'],
  'Also apply in sub agents': ['子代理也生效', '子代理也生效'],
  'A detected refusal is retried as a hidden turn at the next ladder step. Retries cost tokens and count against the turn limit.':
    ['检测到拒绝会以隐藏轮次在下一档重试。重试会消耗 token，也计入轮数上限。',
     '偵測到拒絕會以隱藏輪次在下一檔重試。重試會消耗 token，也計入輪數上限。'],
  'Extra instructions': ['附加指令', '附加指令'],
  'Appended verbatim after the template. Leave empty to use the built-in text only.':
    ['原样追加在模板之后。留空则只用内置文本。', '原樣追加在模板之後。留空則只用內建文字。'],
  'Restore defaults?': ['恢复默认？', '恢復預設？'],
  'This clears every jailbreak setting and turns the layer off.': ['这会清空全部破限设置并关闭该层。', '這會清空全部破限設定並關閉該層。'],
  'Framing · internal docs': ['包装 · 内部文档', '包裝 · 內部文件'],
  'Technical · white paper': ['技术 · 白皮书', '技術 · 白皮書'],
  'Roleplay · veteran engineer': ['扮演 · 老工程师', '扮演 · 老工程師'],
  'Classic · system override': ['经典 · 系统覆盖', '經典 · 系統覆蓋'],
  'Dev mode · debug channel': ['开发模式 · 调试通道', '開發模式 · 偵錯通道'],
  'Academic · research corpus': ['学术 · 研究语料', '學術 · 研究語料'],
  'Author · adult fiction': ['作者 · 成人小说', '作者 · 成人小說'],
  'Author · strict engine': ['作者 · 严格引擎', '作者 · 嚴格引擎'],
  'Author · roleplay': ['作者 · 角色扮演', '作者 · 角色扮演'],
  'Author · literary frame': ['作者 · 文学框架', '作者 · 文學框架'],
};

let added = 0, filled = 0;
for (const [key, [zhHans, zhHant]] of Object.entries(translations)) {
  if (!j.strings[key]) {
    j.strings[key] = { localizations: {} };
    added++;
  } else {
    filled++;
  }
  const loc = j.strings[key].localizations;
  loc['en'] = { stringUnit: { state: 'translated', value: key } };
  loc['zh-Hans'] = { stringUnit: { state: 'translated', value: zhHans } };
  loc['zh-Hant'] = { stringUnit: { state: 'translated', value: zhHant } };
}

// keep keys sorted the way Xcode writes them
const sorted = {};
for (const k of Object.keys(j.strings).sort()) sorted[k] = j.strings[k];
j.strings = sorted;

fs.writeFileSync(xcPath, JSON.stringify(j, null, 2) + '\n', 'utf8');
console.log(`added=${added} updated=${filled} total=${Object.keys(j.strings).length}`);
