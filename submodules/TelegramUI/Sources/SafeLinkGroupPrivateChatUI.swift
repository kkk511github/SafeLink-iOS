import Foundation
import Display
import SwiftSignalKit
import AccountContext
import Postbox
import TelegramCore
import TelegramPresentationData
import UndoUI

func safeLinkGroupPrivateChatForbiddenText() -> String {
    return "此群已禁止与普通成员私聊"
}

// nil means permission could not be confirmed, never permission to navigate.
func safeLinkCanOpenPrivateChatFromGroup(context: AccountContext, groupPeerId: PeerId?, targetPeerId: PeerId) -> Signal<Bool?, NoError> {
    guard let groupPeerId, groupPeerId != targetPeerId, targetPeerId != context.account.peerId, targetPeerId.namespace == Namespaces.Peer.CloudUser else {
        return .single(true)
    }
    
    return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: groupPeerId))
    |> mapToSignal { groupPeer -> Signal<Bool?, NoError> in
        guard let groupPeer else {
            return .single(nil)
        }
        guard case let .channel(channel) = groupPeer, case .group = channel.info else {
            return .single(true)
        }
        if safeLinkCurrentUserCanBypassGroupPrivateChatForbidden(groupPeer) {
            return .single(true)
        }
        return safeLinkRequestGroupPrivateChatForbidden(account: context.account, peerId: groupPeerId)
        |> mapToSignal { forbidden -> Signal<Bool?, NoError> in
            guard let forbidden else {
                return .single(nil)
            }
            if !forbidden {
                return .single(true)
            }
            return context.engine.peers.fetchChannelParticipant(peerId: groupPeerId, participantId: targetPeerId)
            |> map { participant -> Bool? in
                guard let participant else {
                    return nil
                }
                return safeLinkChannelParticipantCanBeContacted(participant)
            }
        }
    }
    |> timeout(8.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

func safeLinkDisplayPrivateChatForbidden(controller: ViewController?, presentationData: PresentationData, unavailable: Bool = false) {
    controller?.displayNode.layer.addShakeAnimation(amplitude: -6.0, decay: true)
    controller?.present(
        UndoOverlayController(
            presentationData: presentationData,
            content: .actionSucceeded(title: nil, text: unavailable ? "暂时无法确认群聊权限，请稍后重试" : safeLinkGroupPrivateChatForbiddenText(), cancel: nil, destructive: false),
            elevatedLayout: false,
            animateInAsReplacement: false,
            action: { _ in return false }
        ),
        in: .current
    )
}
