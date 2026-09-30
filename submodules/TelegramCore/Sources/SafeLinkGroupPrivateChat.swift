import Foundation
import SwiftSignalKit
import Postbox
import TelegramApi

private struct SafeLinkGroupPrivateChatKey: Hashable {
    let accountId: AccountRecordId
    let peerId: PeerId
}

private let safeLinkGroupPrivateChatForbiddenState = Atomic<[SafeLinkGroupPrivateChatKey: Bool]>(value: [:])

public func safeLinkGroupPrivateChatForbiddenCached(accountId: AccountRecordId, peerId: PeerId) -> Bool {
    let key = SafeLinkGroupPrivateChatKey(accountId: accountId, peerId: peerId)
    return safeLinkGroupPrivateChatForbiddenState.with { values in
        return values[key] ?? false
    }
}

private func updateSafeLinkGroupPrivateChatForbiddenCached(accountId: AccountRecordId, peerId: PeerId, value: Bool) {
    let key = SafeLinkGroupPrivateChatKey(accountId: accountId, peerId: peerId)
    let _ = safeLinkGroupPrivateChatForbiddenState.modify { values in
        var values = values
        values[key] = value
        return values
    }
}

public func safeLinkSetGroupPrivateChatForbiddenCached(accountId: AccountRecordId, peerId: PeerId, value: Bool) {
    updateSafeLinkGroupPrivateChatForbiddenCached(accountId: accountId, peerId: peerId, value: value)
}

public func safeLinkCurrentUserCanBypassGroupPrivateChatForbidden(_ peer: EnginePeer?) -> Bool {
    guard case let .channel(channel) = peer, case .group = channel.info else {
        return true
    }
    return channel.flags.contains(.isCreator) || channel.adminRights != nil
}

public func safeLinkChannelParticipantCanBeContacted(_ participant: ChannelParticipant?) -> Bool {
    guard let participant = participant else {
        return false
    }
    switch participant {
    case .creator:
        return true
    case let .member(_, _, adminInfo, _, _, _):
        return adminInfo != nil
    }
}

public func safeLinkLoadGroupPrivateChatForbidden(account: Account, peerId: PeerId) -> Signal<Bool, NoError> {
    return safeLinkRequestGroupPrivateChatForbidden(account: account, peerId: peerId)
    |> map { value in
        return value ?? safeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId)
    }
}

// Navigation must distinguish a confirmed disabled policy from a failed request.
public func safeLinkRequestGroupPrivateChatForbidden(account: Account, peerId: PeerId) -> Signal<Bool?, NoError> {
    return account.postbox.transaction { transaction -> Api.InputChannel? in
        return transaction.getPeer(peerId).flatMap(apiInputChannel)
    }
    |> mapToSignal { inputChannel -> Signal<Bool?, NoError> in
        guard let inputChannel = inputChannel else {
            return .single(nil)
        }
        return account.network.request(Api.functions.safelink.getGroupPrivateChatForbidden(channel: inputChannel))
        |> map { result -> Bool? in
            let value: Bool
            switch result {
            case .boolTrue:
                value = true
            case .boolFalse:
                value = false
            }
            updateSafeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId, value: value)
            return value
        }
        |> `catch` { _ -> Signal<Bool?, NoError> in
            return .single(nil)
        }
    }
}

public func safeLinkSetGroupPrivateChatForbidden(account: Account, peerId: PeerId, enabled: Bool) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction -> Api.InputChannel? in
        return transaction.getPeer(peerId).flatMap(apiInputChannel)
    }
    |> mapToSignal { inputChannel -> Signal<Bool, NoError> in
        guard let inputChannel = inputChannel else {
            return .single(safeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId))
        }
        let previousValue = safeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId)
        updateSafeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId, value: enabled)
        return account.network.request(Api.functions.safelink.toggleGroupPrivateChatForbidden(channel: inputChannel, enabled: enabled ? .boolTrue : .boolFalse))
        |> map { updates -> Bool in
            account.stateManager.addUpdates(updates)
            updateSafeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId, value: enabled)
            return enabled
        }
        |> `catch` { _ -> Signal<Bool, NoError> in
            updateSafeLinkGroupPrivateChatForbiddenCached(accountId: account.id, peerId: peerId, value: previousValue)
            return .single(previousValue)
        }
    }
}
