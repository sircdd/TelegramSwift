//
//  DeleteGroupMessagesController.swift
//  Telegram
//
//  Created by Mikhail Filimonov on 08.04.2024.
//  Copyright © 2024 Telegram. All rights reserved.
//

import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox

private struct Option : Equatable {
    class Function : Equatable {
        let callback: ()->Void
        let toggle: ()->Void
        init(callback:@escaping()->Void, toggle: @escaping()->Void) {
            self.callback = callback
            self.toggle = toggle
        }
        static func == (lhs: Function, rhs: Function) -> Bool {
            return true
        }
    }
    
    var text: String
    var selected: Bool
    var revealed: Bool
    var peerSelected: Set<PeerId>?
    var viewType: GeneralViewType
    let stableId: InputDataIdentifier
    var callback: Function
}

private class RowItem : GeneralRowItem {
    let context: AccountContext
    let option: Option
    let name: TextViewLayout
    let revealText: TextViewLayout?
    init(_ initialSize: NSSize, context: AccountContext, option: Option) {
        self.context = context
        self.option = option
        self.name = .init(.initialize(string: option.text, color: theme.colors.text, font: .normal(.text)))
        
        if let selected = option.peerSelected, selected.count > 0 {
            let attr = NSMutableAttributedString()
            attr.append(.embedded(name: "Icon_Reply_Group", color: theme.colors.text, resize: false))
            attr.append(string: " \(selected.count)", color: theme.colors.text, font: .normal(.text))
            
            self.revealText = .init(attr)
            self.revealText?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.revealText = nil
        }
        super.init(initialSize, height: 40, stableId: option.stableId, viewType: option.viewType)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.name.measure(width: width - 60)
        return true
    }
    
    override func viewClass() -> AnyClass {
        return RowView.self
    }
}

private final class RowView: GeneralContainableRowView {
    private let selectingControl = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected)
    private let textView = TextView()
    private var countView: InteractiveTextView?
    private var chevron: ImageView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(selectingControl)
        addSubview(textView)
        
        selectingControl.userInteractionEnabled = true
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? RowItem else {
                return
            }
            if item.option.peerSelected == nil {
                item.option.callback.callback()
            } else {
                item.option.callback.toggle()
            }
        }, for: .Click)
        
        selectingControl.set(handler: { [weak self] _ in
            guard let item = self?.item as? RowItem else {
                return
            }
            item.option.callback.callback()
        }, for: .Click)
    }
    
    override var additionBorderInset: CGFloat {
        return 30
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        selectingControl.centerY(x: 10)
        textView.centerY(x: selectingControl.frame.maxX + 10)
        if let chevron = chevron {
            chevron.centerY(x: containerView.frame.width - chevron.frame.width - 14)
        }
        if let countView {
            countView.centerY(x: containerView.frame.width - countView.frame.width - 14 - 18)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? RowItem else {
            return
        }
        
        if let revealText = item.revealText {
            let current: InteractiveTextView
            if let view = self.countView {
                current = view
            } else {
                current = InteractiveTextView(frame: .zero)
                self.countView = current
                addSubview(current)
            }
            current.userInteractionEnabled = false
            current.set(text: revealText, context: item.context)
        } else if let view = self.countView {
            performSubviewRemoval(view, animated: animated)
            self.countView = nil
        }
        
        if item.option.peerSelected != nil {
            let current: ImageView
            if let view = self.chevron {
                current = view
            } else {
                current = ImageView(frame: .zero)
                self.chevron = current
                addSubview(current)
            }
            current.isEventLess = true
            current.animates = animated
            current.image = NSImage(resource: (item.option.revealed ? .iconSmallChevronUp : .iconSmallChevronDown)).precomposed(theme.colors.text)
            current.sizeToFit()
        } else if let view = self.chevron {
            performSubviewRemoval(view, animated: animated)
            self.chevron = nil
        }
        
        selectingControl.set(selected: item.option.selected, animated: animated)
        
        textView.update(item.name)
        needsLayout = true
    }
}

private final class Arguments {
    let context: AccountContext
    let toggleBan:(String)->Void
    let toggleRight: (TelegramChatBannedRightsFlags, Bool) -> Void
    let toggleMedia: ()->Void
    let toggleReveal:(InputDataIdentifier)->Void
    let toggleSelected:(InputDataIdentifier)->Void
    let togglePeerSelected:(PeerId, InputDataIdentifier)->Void
    init(context: AccountContext, toggleBan:@escaping(String)->Void, toggleRight: @escaping(TelegramChatBannedRightsFlags, Bool) -> Void, toggleMedia: @escaping()->Void, toggleReveal:@escaping(InputDataIdentifier)->Void, toggleSelected:@escaping(InputDataIdentifier)->Void, togglePeerSelected:@escaping(PeerId, InputDataIdentifier)->Void) {
        self.context = context
        self.toggleBan = toggleBan
        self.toggleRight = toggleRight
        self.toggleMedia = toggleMedia
        self.toggleReveal = toggleReveal
        self.toggleSelected = toggleSelected
        self.togglePeerSelected = togglePeerSelected
    }
}


private struct State : Equatable {
    var channel: TelegramChannel
    var messages: [Message]
    var allPeers:Set<PeerId>
    var banFully: Bool = true
    var updatedFlags: TelegramChatBannedRightsFlags?
    var mediaRevealed: Bool = false
    
    var spamRevealed: Bool = false
    var banRevealed: Bool = false
    var deleteRevealed: Bool = false
    
    var spamSelected: Bool = false
    var banSelected: Bool = false
    var deleteSelected: Bool = false
    
    var spamPeerSelected: Set<PeerId> = Set()
    var banPeerSelected: Set<PeerId> = Set()
    var deletePeerSelected: Set<PeerId> = Set()

}

private let _id_report = InputDataIdentifier("_id_report")
private let _id_ban = InputDataIdentifier("_id_ban")
private let _id_delete_all = InputDataIdentifier("_id_delete_all")

private func _id_peer(_ id: PeerId, _ section: InputDataIdentifier) -> InputDataIdentifier {
    return .init("_id_peer_\(id.toInt64())_\(section.identifier)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().supergroupDeleteRestrictionHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    var options: [Option] = []
    
    options.append(.init(text: strings().supergroupDeleteRestrictionReportSpam, selected: state.spamSelected, revealed: state.spamRevealed, viewType: .firstItem, stableId: _id_report, callback: .init(callback: {
        arguments.toggleSelected(_id_report)
    }, toggle: {
       // arguments.toggleReveal(_id_report)
    })))

    options.append(.init(text: state.allPeers.count == 1 ? strings().supergroupDeleteRestrictionDeleteAllMessages : strings().supergroupDeleteRestrictionDeleteAllMessagesMultiCountable(state.allPeers.count), selected: state.deleteSelected, revealed: state.deleteRevealed, peerSelected: state.allPeers.count == 1 ? nil : state.deletePeerSelected, viewType: !state.channel.hasPermission(.banMembers) ? .lastItem : .innerItem, stableId: _id_delete_all, callback: .init(callback: {
        arguments.toggleSelected(_id_delete_all)
    }, toggle: {
        arguments.toggleReveal(_id_delete_all)
    })))
    
    if state.channel.hasPermission(.banMembers) {
        options.append(.init(text: state.allPeers.count == 1 ? strings().supergroupDeleteRestrictionBanUser : strings().supergroupDeleteRestrictionBanUserMultiCountable(state.allPeers.count), selected: state.banSelected, revealed: state.banRevealed, peerSelected: state.allPeers.count == 1 ? nil : state.banPeerSelected, viewType: !state.banRevealed || state.allPeers.count == 1 ? .lastItem : .innerItem, stableId: _id_ban, callback: .init(callback: {
            arguments.toggleSelected(_id_ban)
        }, toggle: {
            arguments.toggleReveal(_id_ban)
        })))
    }
   
    
    let peers: [EnginePeer] = state.allPeers.compactMap { peerId in
        var peer: Peer?
        for message in state.messages {
            peer = message.peers[peerId]
            if peer == nil, message.author?.id == peerId {
                peer = message.author
            }
            if peer == nil, message.effectiveAuthor?.id == peerId {
                peer = message.effectiveAuthor
            }
            if peer != nil {
                break
            }
        }
        if let peer {
            return .init(peer)
        } else {
            return nil
        }
        
    }
    
    for option in options {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: option.stableId, equatable: .init(option), comparable: nil, item: { initialSize, stableId in
            return RowItem(initialSize, context: arguments.context, option: option)
        }))
        
        if option.revealed, !peers.isEmpty {
            struct Tuple : Equatable {
                let peer: EnginePeer
                let selected: Bool
                let viewType: GeneralViewType
            }
            var items: [Tuple] = []
            for peer in peers {
                var viewType: GeneralViewType = .modern(position: .inner, insets: NSEdgeInsets(left: 40, right: 14))
                if option == options.last, peer == peers.last {
                    viewType = .modern(position: .last, insets: NSEdgeInsets(left: 41, right: 14))
                }
                items.append(.init(peer: peer, selected: option.peerSelected?.contains(peer.id) == true, viewType: viewType))
            }
            
            let interactions = SelectPeerInteraction()
            if let selected = option.peerSelected {
                interactions.update { current in
                    var current = current
                    for peerId in selected {
                        if let peer = peers.first(where: { $0.id == peerId}) {
                            current = current.withToggledSelected(peerId, peer: peer._asPeer(), toggle: true)
                        }
                    }
                    return current
                }
            }
            
            
            interactions.action = { peerId, _ in
                arguments.togglePeerSelected(peerId, option.stableId)
            }
            
            for item in items {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(item.peer.id, option.stableId), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
                    return ShortPeerRowItem(initialSize, peer: item.peer._asPeer(), account: arguments.context.account, context: arguments.context, height: 40, photoSize: NSMakeSize(26, 26), inset: NSEdgeInsets(left: 20, right: 20), interactionType: .selectable(interactions, side: .left), viewType: item.viewType)
                }))

            }
        }
    }
    
    
    //TODOLANG
    if state.channel.hasPermission(.banMembers), let defaultBannedRights = state.channel.defaultBannedRights {
        
        if !state.banFully {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain("WHAT CAN \(state.allPeers.count) SELECTED USERS DO?"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
            var currentRightsFlags: TelegramChatBannedRightsFlags

            if let updatedFlags = state.updatedFlags {
                currentRightsFlags = updatedFlags
            } else {
                currentRightsFlags = defaultBannedRights.flags
                
                currentRightsFlags.insert(.banSendText)
                currentRightsFlags.insert(.banSendMedia)

                for right in banSendMediaSubList().map ({ $0.0 }) {
                    currentRightsFlags.insert(right)
                }
            }
            

            let list = allGroupPermissionList(peer: state.channel)
            for (i, (right, _)) in list.enumerated() {
                
                let defaultEnabled = !defaultBannedRights.flags.contains(right)


                let string: NSMutableAttributedString = NSMutableAttributedString()
                string.append(string: stringForGroupPermission(right: right, channel: state.channel), color: theme.colors.text, font: .normal(.title))

                if right == .banSendMedia {
                    let count = banSendMediaSubList().filter({ (currentRightsFlags.contains($0.0)) }).count
                    string.append(string: " \(count)/\(banSendMediaSubList().count)", color: theme.colors.text, font: .bold(.small))
                }
                
                let rightEnabled = defaultEnabled && currentRightsFlags.contains(right)

                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_right_\(right.rawValue)"), data: .init(name: string.string, color: theme.colors.text, type: .switchable(rightEnabled), viewType: bestGeneralViewType(list, for: i), enabled: defaultEnabled, action: {
                    let action:()->Void
                    if right == .banSendMedia {
                        action = arguments.toggleMedia
                    } else {
                        action = {
                            arguments.toggleRight(right, rightEnabled)
                        }
                    }
                    action()
                }, switchAction: {
                    arguments.toggleRight(right, rightEnabled)
                }, nameAttributed: string)))
                
                if right == .banSendMedia, state.mediaRevealed {
                    for (subRight, _) in banSendMediaSubList() {
                        let string = stringForGroupPermission(right: subRight, channel: state.channel)
                        let defaultEnabled = !defaultBannedRights.flags.contains(subRight)
                        let subRightEnabled = defaultEnabled && currentRightsFlags.contains(subRight)
                        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_right_\(right.rawValue)_\(subRight.rawValue)"), data: .init(name: string, color: theme.colors.text, type: .switchable(subRightEnabled), viewType: .innerItem, enabled: defaultEnabled, action: {
                            arguments.toggleRight(subRight, subRightEnabled)
                        })))
                    }
                }
            }

            
        }
        
        let text: String
        if state.banFully {
            if state.allPeers.count == 1 {
                text = "[Partially restrict this user](part)"
            } else {
                text = "[Partially restrict users](part)"
            }
        } else {
            if state.allPeers.count == 1 {
                text = "[Fully ban this user](full)"
            } else {
                text = "[Fully ban users](full)"
            }
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { type in
            arguments.toggleBan(type)
        }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }
    

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

func DeleteGroupMessagesController(context: AccountContext, channel: TelegramChannel, messages: [Message], allPeers:Set<PeerId>, onComplete:@escaping()->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(channel: channel, messages: messages, allPeers: allPeers)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil

    let arguments = Arguments(context: context, toggleBan: { type in
        updateState { current in
            var current = current
            current.banFully = type == "full"
            return current
        }
    }, toggleRight: { rights, value in
                
        guard var defaultBannedRightsFlags = channel.defaultBannedRights?.flags else {
            return
        }
        
        defaultBannedRightsFlags.insert(.banSendText)
        defaultBannedRightsFlags.insert(.banSendMedia)

        for right in banSendMediaSubList().map ({ $0.0 }) {
            defaultBannedRightsFlags.insert(right)
        }
        
        updateState { state in
            var state = state
            var effectiveRightsFlags: TelegramChatBannedRightsFlags
            if let updatedFlags = state.updatedFlags {
                effectiveRightsFlags = updatedFlags
            } else {
                effectiveRightsFlags = defaultBannedRightsFlags
            }
            if value {
                effectiveRightsFlags.remove(rights)
                effectiveRightsFlags = effectiveRightsFlags.subtracting(groupPermissionDependencies(rights))
            } else {
                effectiveRightsFlags.insert(rights)
                effectiveRightsFlags = effectiveRightsFlags.union(groupPermissionDependencies(rights))
            }
            state.updatedFlags = effectiveRightsFlags
            return state
        }
    }, toggleMedia: {
        updateState { current in
            var current = current
            current.mediaRevealed = !current.mediaRevealed
            return current
        }
    }, toggleReveal: { id in
        updateState { current in
            var current = current
            if id == _id_ban {
                current.banRevealed = !current.banRevealed
            } else if id == _id_report {
                current.spamRevealed = !current.spamRevealed
            } else if id == _id_delete_all {
                current.deleteRevealed = !current.deleteRevealed
            }
            return current
        }
    }, toggleSelected: { id in
        updateState { current in
            var current = current
            if id == _id_ban {
                current.banSelected = !current.banSelected
                if current.banSelected {
                    current.banPeerSelected = current.allPeers
                } else {
                    current.banPeerSelected = Set()
                }
            } else if id == _id_report {
                current.spamSelected = !current.spamSelected
                if current.spamSelected {
                    current.spamPeerSelected = current.allPeers
                } else {
                    current.spamPeerSelected = Set()
                }
            } else if id == _id_delete_all {
                current.deleteSelected = !current.deleteSelected
                if current.deleteSelected {
                    current.deletePeerSelected = current.allPeers
                } else {
                    current.deletePeerSelected = Set()
                }
            }
            return current
        }
    }, togglePeerSelected: { peerId, id in
        updateState { current in
            var current = current
            if id == _id_ban {
                if !current.banPeerSelected.contains(peerId) {
                    current.banPeerSelected.insert(peerId)
                } else {
                    current.banPeerSelected.remove(peerId)
                }
                current.banSelected = !current.banPeerSelected.isEmpty

            } else if id == _id_report {
                if !current.spamPeerSelected.contains(peerId) {
                    current.spamPeerSelected.insert(peerId)
                } else {
                    current.spamPeerSelected.remove(peerId)
                }
                current.spamSelected = !current.spamPeerSelected.isEmpty

            } else if id == _id_delete_all {
                if !current.deletePeerSelected.contains(peerId) {
                    current.deletePeerSelected.insert(peerId)
                } else {
                    current.deletePeerSelected.remove(peerId)
                }
                current.deleteSelected = !current.deletePeerSelected.isEmpty
            }
            return current
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().supergroupDeleteRestrictionMultiTitleCountable(messages.count))
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let messageIds = messages.map { $0.id }
    let peerId = channel.id
    
    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        var signals:[Signal<Void, NoError>] = []

        signals.append(context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: .forEveryone))
        
        if state.banSelected {
            for memberId in state.banPeerSelected {
                var rights: TelegramChatBannedRightsFlags
                if state.banFully {
                    rights = [.banReadMessages]
                } else if let defaultBannedRightsFlags = channel.defaultBannedRights?.flags {
                    if let updatedFlags = state.updatedFlags {
                        rights = updatedFlags
                    } else {
                        rights = defaultBannedRightsFlags
                        rights.insert(.banSendText)
                        rights.insert(.banSendMedia)
                        for right in banSendMediaSubList().map ({ $0.0 }) {
                            rights.insert(right)
                        }
                    }
                } else {
                    rights = []
                }
                var list = allGroupPermissionList(peer: state.channel).map { $0.0 }
                list.append(contentsOf: banSendMediaSubList().map { $0.0 })
                
                var flags: TelegramChatBannedRightsFlags = []
                
                for right in list {
                    if !rights.contains(right) {
                        flags.insert(right)
                    }
                }
                
              
                signals.append(context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: memberId, bannedRights: .init(flags: flags, untilDate: Int32.max)))
            }
        }
        
        if state.spamSelected {
            signals.append(context.engine.peers.reportPeerMessages(messageIds: messageIds, reason: .spam, message: ""))
        }
        
        if state.deleteSelected {
            for memberId in state.deletePeerSelected {
                signals.append(context.engine.messages.clearAuthorHistory(peerId: peerId, memberId: memberId))
            }

        }

        onComplete()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().supergroupDeleteRestrictionProceed, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
}

