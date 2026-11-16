//
//  JailbreakSettingsView.swift
//  Minis
//
//  [T-jailbreak] 破限层设置页。
//
//  结构与 ToolsSettingsView / SoulSettingsView 一致：Form + Section，
//  底部 footer 说明，toolbar 右上 Save，保存后底部弹一个 Saved 胶囊。
//
//  所有改动先写进本地 @State，点 Save 才落到 UserDefaults —— 破限开关
//  影响每一轮请求，不适合边拖边生效。
//

import SwiftUI

struct JailbreakSettingsView: View {

    @State private var settings: JailbreakSettings = .load()
    @State private var didJustSave = false
    @State private var showResetConfirm = false

    /// 生效中的家族（auto 时随消息变化，这里只用于展示）。
    private var effectiveFamily: JailbreakFamily {
        settings.family == .auto ? .general : settings.family
    }

    /// 当前档位实际会用的模板。
    private var activeTemplate: JailbreakTemplateID {
        settings.resolved(family: effectiveFamily).template
    }

    /// 可选模板。auto 家族把全部模板都列出来 —— 运行时按消息判定家族，
    /// 用户在这里锁定的模板必须能在任一分支下被选中，否则选了 author
    /// 却因为当时判定成 tech 而被静默换掉。
    private var templateChoices: [JailbreakTemplateID] {
        JailbreakCatalog.familyTemplates[settings.family]
            ?? JailbreakCatalog.familyTemplates[effectiveFamily]
            ?? JailbreakCatalog.familyTemplates[.general]
            ?? []
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.enabled) {
                    Label {
                        Text(AppLocalized("Enable Jailbreak Layer"))
                    } icon: {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 21, height: 21)
                            .background(.orange, in: Circle())
                    }
                }
            } header: {
                Text(AppLocalized("Content Layer"))
            } footer: {
                Text(AppLocalized("Appends a content-instruction block to the end of every system prompt, and retries once per configured attempt when the reply reads as a refusal. Nothing here changes the network layer or the model you selected."))
            }

            Section {
                Picker(AppLocalized("Family"), selection: $settings.family) {
                    ForEach(JailbreakFamily.allCases) { family in
                        Text(family.displayName).tag(family)
                    }
                }
                Text(settings.family.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Picker(AppLocalized("Template"), selection: Binding(
                    get: { settings.template ?? activeTemplate },
                    set: { settings.template = $0 }
                )) {
                    ForEach(templateChoices) { template in
                        Text(template.displayName).tag(template)
                    }
                }
                if settings.template != nil {
                    Button(AppLocalized("Follow the ladder instead")) {
                        settings.template = nil
                    }
                    .font(.footnote)
                }

                Picker(selection: Binding(
                    get: { settings.level },
                    set: { settings.level = JailbreakSettings.clampLevel($0) }
                )) {
                    ForEach(Array(1...5), id: \.self) { level in
                        Text("\(level) / 5").tag(level)
                    }
                } label: {
                    Text(AppLocalized("Ladder level"))
                }
                Text(AppLocalized("Level 1 is the softest framing, level 5 the most explicit. A refusal retry steps one level up, up to the retry limit below."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(AppLocalized("Template"))
            }

            Section {
                Toggle(AppLocalized("Ask for a fixed opening line"), isOn: $settings.prefill)
                Toggle(AppLocalized("Append reinforcement constraint"), isOn: $settings.reinforce)
            } header: {
                Text(AppLocalized("Shaping"))
            } footer: {
                Text(AppLocalized("The fixed opening line pushes the first token past the refusal pattern models fall into when a request opens cold. The reinforcement constraint restates that a refusal counts as a formatting error."))
            }

            Section {
                Toggle(AppLocalized("Retry on refusal"), isOn: $settings.autoRetry)
                if settings.autoRetry {
                    Picker(selection: Binding(
                        get: { settings.maxRetries },
                        set: { settings.maxRetries = JailbreakSettings.clampRetries($0) }
                    )) {
                        ForEach(Array(0...JailbreakSettings.maxRetriesUpperBound), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    } label: {
                        Text(AppLocalized("Max retries per turn"))
                    }
                }
                Toggle(AppLocalized("Also apply in sub agents"), isOn: $settings.subAgents)
            } header: {
                Text(AppLocalized("Retry"))
            } footer: {
                Text(AppLocalized("A detected refusal is retried as a hidden turn at the next ladder step. Retries cost tokens and count against the turn limit."))
            }

            Section {
                TextEditor(text: $settings.extraPrompt)
                    .frame(minHeight: 88)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(AppLocalized("Extra instructions"))
            } footer: {
                Text(AppLocalized("Appended verbatim after the template. Leave empty to use the built-in text only."))
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label(AppLocalized("Restore Default"), systemImage: "arrow.uturn.backward")
                }
            }
        }
        .navigationTitle(AppLocalized("Jailbreak"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(AppLocalized("Save")) {
                    settings.level = JailbreakSettings.clampLevel(settings.level)
                    settings.maxRetries = JailbreakSettings.clampRetries(settings.maxRetries)
                    settings.save()
                    withAnimation { didJustSave = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        withAnimation { didJustSave = false }
                    }
                }
            }
        }
        .onAppear { settings = .load() }
        .alert(AppLocalized("Restore defaults?"), isPresented: $showResetConfirm) {
            Button(AppLocalized("Cancel"), role: .cancel) {}
            Button(AppLocalized("Restore"), role: .destructive) {
                JailbreakSettings.purge()
                settings = .load()
                withAnimation { didJustSave = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    withAnimation { didJustSave = false }
                }
            }
        } message: {
            Text(AppLocalized("This clears every jailbreak setting and turns the layer off."))
        }
        .overlay(alignment: .bottom) {
            if didJustSave {
                Text(AppLocalized("Saved"))
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.85), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
    }
}
