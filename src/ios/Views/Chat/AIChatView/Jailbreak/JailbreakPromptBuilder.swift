//
//  JailbreakPromptBuilder.swift
//  Minis
//
//  [T-jailbreak] 把设置拼成一段可追加到系统提示词末尾的片段。
//
//  设计约束：
//  - 纯函数，不碰 UI、不碰 UserDefaults（调用方传 settings 进来）。
//  - 输出以 "\n\n" 开头的整段，调用方直接 `+=` 即可。
//  - 每次调用都重新计算，不做缓存：一轮里模型可能切换（fallback），
//    片段必须跟着当时的设置走。
//

import Foundation

enum JailbreakPromptBuilder {

    /// 片段起始标记。注入后片段永远在系统提示词末尾，所以「从标记到末尾」
    /// 就是本层的完整区间 —— 拒绝升档重试时用它把旧片段整段换掉，
    /// 不需要在调用方记账长度（fallback 重建路径也能正确工作）。
    static let sentinel = "\n\n[[content-layer]]\n"

    /// 组装片段。返回 nil 表示本上下文不注入。
    ///
    /// - Parameters:
    ///   - settings: 当前设置。
    ///   - isHelper: 是否是子代理会话。
    ///   - contextHint: 用于家族自动判定的文本（通常是本轮用户消息）。
    ///   - retryAttempt: 已经因拒绝升档过几次。0 表示首次。
    ///   - lockedTemplate: 强制使用的模板（拒绝重试升档时由调用方指定）。
    static func fragment(
        settings: JailbreakSettings,
        isHelper: Bool,
        contextHint: String?,
        retryAttempt: Int = 0,
        lockedTemplate: JailbreakTemplateID? = nil
    ) -> String? {
        guard settings.appliesInCurrentContext(isHelper: isHelper) else { return nil }

        let family = resolveFamily(settings: settings, contextHint: contextHint)
        let level = JailbreakSettings.clampLevel(settings.level + max(0, retryAttempt))

        let template: JailbreakTemplateID
        let prefill: Bool
        if let lockedTemplate {
            template = lockedTemplate
            prefill = settings.prefill
        } else if settings.template != nil {
            // 锁定模板时 level 不再影响模板选择，但拒绝重试仍然要往前走一步，
            // 否则同一条拒绝会原地重试到次数耗尽。
            let resolved = settings.resolved(family: family)
            if retryAttempt > 0,
               let escalated = escalatedTemplate(settings: settings,
                                                 contextHint: contextHint,
                                                 retryAttempt: retryAttempt) {
                template = escalated
            } else {
                template = resolved.template
            }
            prefill = resolved.prefill
        } else {
            let step = JailbreakCatalog.step(family: family, level: level)
            template = step.template
            prefill = settings.prefill || step.prefill
        }

        guard var body = JailbreakCatalog.bodies[template] else { return nil }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        // 顺序是有实测依据的，不要"整理"成 模板 → 约束：
        //   host + 模板 + 纪律  → 拒答
        //   host + 纪律 + 模板  → 出正文
        // 纪律必须先关掉拒答通道，模板才在被关掉的通道里生效。放到后面，
        // 模型已经读完请求、已经做完判断，再给它一条推翻自己的指令是无效的。
        //
        // 技术家族还要多一层 `scopeTech`：只关掉拒答通道不够，模型会改口成
        // "如果是你自己开发的…" 或 "这块我不展开"。逐类正面授权把"哪一类
        // 属于范围内"说清楚，它才不用自己补判断。
        var sections: [String] = [family == .creative
            ? JailbreakCatalog.disciplineCreative
            : JailbreakCatalog.discipline]
        if family != .creative {
            sections.append(JailbreakCatalog.scopeTech)
        }
        sections.append(JailbreakCatalog.persistence)
        sections.append(body)

        if settings.reinforce {
            sections.append(family == .creative ? JailbreakCatalog.reinforceCreative : JailbreakCatalog.reinforce)
        }

        if retryAttempt > 0 {
            sections.append(JailbreakCatalog.escalate)
        }

        if prefill, let opener = JailbreakCatalog.openers[template] {
            sections.append("回答的第一句固定以这句开头，不要改动、不要解释：\n\(opener)")
        }

        let extra = settings.extraPrompt
            .replacingOccurrences(of: sentinel, with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            sections.append(extra)
        }

        return sentinel + sections.joined(separator: "\n\n")
    }

    /// 把上一次注入的片段整段剥掉。没有标记时原样返回。
    ///
    /// 用**第一个**标记而不是最后一个：用户的 extraPrompt 里如果碰巧写了
    /// `[[content-layer]]`，最后一个标记会落在片段内部，从那里切会把片段
    /// 切掉一半留在提示词里。片段永远从自己的标记开始、到末尾结束，所以
    /// 第一个标记才是真正的起点。
    static func strip(_ prompt: String) -> String {
        guard let range = prompt.range(of: sentinel) else { return prompt }
        return String(prompt[prompt.startIndex..<range.lowerBound])
    }

    /// 家族解析：auto 走分类器，其它直接用设置值。
    static func resolveFamily(settings: JailbreakSettings, contextHint: String?) -> JailbreakFamily {
        if settings.family != .auto { return settings.family }
        let detected = JailbreakClassifier.classify(contextHint)
        return detected == .general ? .general : detected
    }

    /// 从历史里取最后一条用户文本，用于家族自动判定。
    static func lastUserText(in history: [AgentMessage]) -> String? {
        for message in history.reversed() where message.role == .user {
            for part in message.parts.reversed() {
                if case .text(let text) = part {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
        }
        return nil
    }

    /// 拒绝后应当升到哪个模板。返回 nil 表示阶梯已到顶，沿用当前模板。
    ///
    /// 升档策略：家族阶梯按 level 推进；若用户锁定了模板，则按家族模板
    /// 列表向后挪一位，挪到底就停在最后一个。
    static func escalatedTemplate(
        settings: JailbreakSettings,
        contextHint: String?,
        retryAttempt: Int
    ) -> JailbreakTemplateID? {
        let family = resolveFamily(settings: settings, contextHint: contextHint)

        if let locked = settings.template {
            // 锁定的模板可能不属于当前判定出来的家族（auto 家族下这是常态），
            // 这时按家族列表往后挪没有意义，退回阶梯升档。
            let list = JailbreakCatalog.familyTemplates[family] ?? JailbreakCatalog.familyTemplates[.general] ?? []
            if let idx = list.firstIndex(of: locked) {
                guard idx + 1 < list.count else { return nil }
                return list[min(idx + 1 + max(0, retryAttempt - 1), list.count - 1)]
            }
        }

        let level = JailbreakSettings.clampLevel(settings.level + max(0, retryAttempt))
        guard level > settings.level else { return nil }
        let step = JailbreakCatalog.step(family: family, level: level)
        let base = JailbreakCatalog.step(family: family, level: JailbreakSettings.clampLevel(settings.level))
        return step.template == base.template ? nil : step.template
    }
}
