import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import AccountContext
import TelegramPresentationData
import ItemListUI

private struct SafeLinkServerEntry: ItemListNodeEntry {
    let section: ItemListSectionId
    let stableId: String
    let order: Int
    let title: String
    let label: String
    let server: SafeLinkServer?
    let accountId: AccountRecordId?
    let account: AccountWithInfo?
    let isAction: Bool
    var isHeader: Bool = false
    var isCurrent: Bool = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.section == rhs.section && lhs.stableId == rhs.stableId && lhs.order == rhs.order && lhs.title == rhs.title && lhs.label == rhs.label && lhs.server == rhs.server && lhs.accountId == rhs.accountId && lhs.account == rhs.account && lhs.isAction == rhs.isAction && lhs.isHeader == rhs.isHeader && lhs.isCurrent == rhs.isCurrent
    }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.order < rhs.order }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let actions = arguments as! SafeLinkServerActions
        if isHeader {
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, accessoryText: ItemListSectionHeaderAccessoryText(value: label, color: .generic), sectionId: section)
        }
        if isAction {
            return ItemListActionItem(presentationData: presentationData, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: { actions.activate(self) })
        }
        return ItemListDisclosureItem(presentationData: presentationData, context: account.flatMap { actions.contexts[$0.account.id] }, iconPeer: account?.peer, displaySavedMessagesIcon: false, title: title, titleFont: accountId == nil ? .regular : .bold, titleBadge: isCurrent ? "当前" : nil, label: label, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, disclosureStyle: accountId == nil ? .arrow : .none, action: { actions.activate(self) })
    }
}

private final class SafeLinkServerActions {
    let sharedContext: SharedAccountContext
    let rootPath: String
    let changed = ValuePromise<Int>(0, ignoreRepeated: false)
    let discovery = SafeLinkServerDiscovery()
    weak var controller: ViewController?
    var contexts: [AccountRecordId: AccountContext] = [:]
    var accountLimit = 3
    var adding = false

    init(sharedContext: SharedAccountContext, rootPath: String) {
        self.sharedContext = sharedContext
        self.rootPath = rootPath
    }
    deinit { discovery.cancel() }

    func alert(_ message: String) {
        let alert = UIAlertController(title: "SafeLink", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        controller?.present(alert, animated: true)
    }

    func activate(_ entry: SafeLinkServerEntry) {
        if let accountId = entry.accountId {
            guard !entry.isCurrent else { return }
            controller?.dismiss()
            sharedContext.switchToAccount(id: accountId, fromSettingsController: nil, withChatListController: nil)
        } else if let server = entry.server {
            if entry.isAction {
                guard contexts.count < accountLimit else { alert("已达到当前客户端的账号数量上限，请先退出一个账号。"); return }
                sharedContext.beginNewAuth(server: server, completion: { [weak self] success in
                    if success { self?.controller?.dismiss() } else { self?.alert("无法保存服务器账号配置，请重试。") }
                })
            } else {
                alert("\(server.name)\n\(server.address)\n\n公钥 SHA-256\n\(server.serverId)\n\nMTProto 指纹\n\(server.rsaFingerprint)")
            }
        } else if entry.isAction { addServer() }
    }

    func addServer() {
        guard !adding else { return }
        let alert = UIAlertController(title: "添加服务器", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.placeholder = "IP 或 HTTPS 地址"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "下一步", style: .default, handler: { [weak self, weak alert] _ in
            guard let self, let address = alert?.textFields?.first?.text else { return }
            self.adding = true
            self.changed.set(0)
            self.discovery.fetch(address: address, completion: { [weak self] result in
                guard let self else { return }
                self.adding = false
                self.changed.set(0)
                switch result {
                case let .failure(error): self.alert(error.localizedDescription)
                case let .success(server): self.confirm(server)
                }
            })
        }))
        controller?.present(alert, animated: true)
    }

    func confirm(_ server: SafeLinkServer) {
        let alert = UIAlertController(title: "确认服务器", message: "\(server.name)\n\(server.address)\n\n公钥 SHA-256\n\(server.serverId)\n\n请确认这是你信任的服务器。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "添加", style: .default, handler: { [weak self] _ in
            guard let self else { return }
            do {
                try server.save(rootPath: self.rootPath)
                self.changed.set(0)
            } catch { self.alert(error.localizedDescription) }
        }))
        controller?.present(alert, animated: true)
    }
}

func safeLinkServersController(sharedContext: SharedAccountContext, rootPath: String) -> ViewController {
    let actions = SafeLinkServerActions(sharedContext: sharedContext, rootPath: rootPath)
    let signal = combineLatest(sharedContext.presentationData, sharedContext.activeAccountsWithInfo, sharedContext.activeAccountContexts, actions.changed.get())
    |> deliverOnMainQueue
    |> map { presentationData, info, contexts, _ -> (ItemListControllerState, (ItemListNodeState, SafeLinkServerActions)) in
        actions.contexts = Dictionary(uniqueKeysWithValues: contexts.accounts.map { ($0.0, $0.1) })
        actions.accountLimit = info.accounts.contains(where: { $0.peer.isPremium }) ? 4 : 3
        var entries: [SafeLinkServerEntry] = []
        var servers: [SafeLinkServer] = []
        var loadError: String?
        do { servers = try SafeLinkServer.saved(rootPath: rootPath) } catch { loadError = error.localizedDescription }
        for account in info.accounts where !servers.contains(where: { $0.serverId == account.account.network.safeLinkServer.serverId }) {
            servers.append(account.account.network.safeLinkServer)
        }
        for (section, server) in servers.enumerated() {
            let accounts = info.accounts.filter { $0.account.network.safeLinkServer.serverId == server.serverId }
            let current = accounts.contains { $0.account.id == info.primary }
            entries.append(SafeLinkServerEntry(section: Int32(section), stableId: "header:\(server.serverId)", order: entries.count, title: server.name, label: current ? "当前服务器 · \(accounts.count) 个账号" : "\(accounts.count) 个账号", server: nil, accountId: nil, account: nil, isAction: false, isHeader: true))
            entries.append(SafeLinkServerEntry(section: Int32(section), stableId: "server:\(server.serverId)", order: entries.count, title: "服务器信息", label: server.address, server: server, accountId: nil, account: nil, isAction: false))
            for account in accounts {
                let username = account.peer.addressName.flatMap { $0.isEmpty ? nil : "@\($0)" } ?? ""
                entries.append(SafeLinkServerEntry(section: Int32(section), stableId: "account:\(account.account.id)", order: entries.count, title: account.peer.compactDisplayTitle, label: username, server: server, accountId: account.account.id, account: account, isAction: false, isCurrent: account.account.id == info.primary))
            }
            entries.append(SafeLinkServerEntry(section: Int32(section), stableId: "add-account:\(server.serverId)", order: entries.count, title: "添加账号", label: "", server: server, accountId: nil, account: nil, isAction: true))
        }
        if let loadError {
            entries.append(SafeLinkServerEntry(section: Int32(servers.count), stableId: "error", order: entries.count, title: "读取服务器配置失败", label: loadError, server: nil, accountId: nil, account: nil, isAction: false))
        } else {
            entries.append(SafeLinkServerEntry(section: Int32(servers.count), stableId: "add-server", order: entries.count, title: actions.adding ? "正在验证服务器…" : "添加服务器", label: "", server: nil, accountId: nil, account: nil, isAction: true))
        }
        let data = ItemListPresentationData(presentationData)
        let addButton = ItemListNavigationButton(content: .icon(.add), style: actions.adding ? .activity : .regular, enabled: !actions.adding && loadError == nil, action: { actions.addServer() })
        let state = ItemListControllerState(presentationData: data, title: .text("服务器与账号"), leftNavigationButton: nil, rightNavigationButton: addButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: true), actions))
    }
    let controller = ItemListController(presentationData: ItemListPresentationData(sharedContext.currentPresentationData.with { $0 }), updatedPresentationData: sharedContext.presentationData |> map(ItemListPresentationData.init), state: signal, tabBarItem: nil)
    actions.controller = controller
    return controller
}
