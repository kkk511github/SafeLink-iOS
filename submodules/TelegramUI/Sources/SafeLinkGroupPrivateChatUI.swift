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

func safeLinkCanOpenPrivateChatFromGroup(context: AccountContext, groupPeerId: PeerId?, targetPeerId: PeerId) -> Signal<Bool, NoError> {
    guard let groupPeerId, groupPeerId != targetPeerId, targetPeerId != context.account.peerId else {
        return .single(true)
    }
    guard safeLinkGroupPrivateChatForbiddenCached(accountPeerId: context.account.peerId, peerId: groupPeerId) else {
        return .single(true)
    }
    
    return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: groupPeerId))
    |> mapToSignal { groupPeer -> Signal<Bool, NoError> in
        guard case .channel = groupPeer else {
            return .single(true)
        }
        if safeLinkCurrentUserCanBypassGroupPrivateChatForbidden(groupPeer) {
            return .single(true)
        }
        return context.engine.peers.fetchChannelParticipant(peerId: groupPeerId, participantId: targetPeerId)
        |> map { participant -> Bool in
            return safeLinkChannelParticipantCanBeContacted(participant)
        }
    }
}

func safeLinkDisplayPrivateChatForbidden(controller: ViewController?, presentationData: PresentationData) {
    controller?.present(
        UndoOverlayController(
            presentationData: presentationData,
            content: .actionSucceeded(title: nil, text: safeLinkGroupPrivateChatForbiddenText(), cancel: nil, destructive: false),
            elevatedLayout: false,
            animateInAsReplacement: false,
            action: { _ in return false }
        ),
        in: .current
    )
}
