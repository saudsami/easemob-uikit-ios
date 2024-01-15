import UIKit
import MobileCoreServices
import QuickLook
import AVFoundation

/// An enumeration representing different types of chats.
@objc public enum ChatType: UInt {
    case chat
    case group
    case chatroom
    case thread
}

@objcMembers open class MessageListController: UIViewController {
    
    public var filePath = ""
    
    private var chatType = ChatType.chat
    
    public private(set) var profile: EaseProfileProtocol = EaseProfile()
    
    public private(set) lazy var navigation: EaseChatNavigationBar = {
        self.createNavigation()
    }()
        
    /// Creates a navigation bar for the MessageListController.
    /// - Returns: An instance of EaseChatNavigationBar.
    @objc open func createNavigation() -> EaseChatNavigationBar {
        EaseChatNavigationBar(showLeftItem: true,rightImages: [UIImage(named: "audio_call", in: .chatBundle, with: nil)!,UIImage(named: "video_call", in: .chatBundle, with: nil)!]).backgroundColor(.clear)
    }
    
    public private(set) lazy var messageContainer: MessageListView = {
        MessageListView(frame: CGRect(x: 0, y: self.navigation.frame.maxY, width: self.view.frame.width, height: self.view.frame.height-NavigationHeight), mention: self.chatType == .group)
    }()
    
    public private(set) lazy var loadingView: LoadingView = {
        self.createLoading()
    }()
    
    /**
     Creates a loading view.
     
     - Returns: A `LoadingView` instance.
     */
    @objc open func createLoading() -> LoadingView {
        LoadingView(frame: self.view.bounds)
    }
    
    public private(set) lazy var viewModel: MessageListViewModel = { ComponentsRegister.shared.MessagesViewModel.init(conversationId: self.profile.id, type: self.chatType) }()
    
    /**
     Initializes a new instance of the `MessageListController` class with the specified conversation ID and chat type.
     
     - Parameters:
         - conversationId: The ID of the conversation.
         - chatType: The type of chat. Default value is `.chat`.
     
     This initializer sets the `profile` property based on the conversation ID. If the conversation ID is found in the conversations cache, the profile is set to the corresponding information. Otherwise, the profile ID is set to the conversation ID.
     
     The `chatType` parameter determines the type of chat, which can be `.group`, `.thread`, or `.chat`. If the chat type is not one of these options, it defaults to `.chatroom`.
     */
    @objc(initWithConversationId:chatType:)
    public required init(conversationId: String,chatType: ChatType = .chat) {
        if let info = EaseChatUIKitContext.shared?.conversationsCache?[conversationId] {
            self.profile = info
        } else {
            self.profile.id = conversationId
        }
        switch chatType {
        case .group,.thread:
            self.chatType = .group
        case .chat:
            self.chatType = .chat
        default:
            self.chatType = .chatroom
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
     }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        AudioTools.shared.stopPlaying()
        self.messageContainer.messages.forEach { $0.playing = false }
        self.messageContainer.messageList.reloadData()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = UIColor.theme.neutralColor98
        self.navigation.subtitle = "online"
        self.navigation.title = self.profile.nickname.isEmpty ? self.profile.id:self.profile.nickname
        self.view.addSubViews([self.navigation,self.messageContainer])
        self.navigation.clickClosure = { [weak self] in
            self?.navigationClick(type: $0, indexPath: $1)
        }
        
        self.viewModel.bindDriver(driver: self.messageContainer)
        self.viewModel.addEventsListener(self)
        Theme.registerSwitchThemeViews(view: self)
        self.switchTheme(style: Theme.style)
        self.view.addSubview(self.loadingView)
    }
    
    deinit {
        EaseChatUIKitContext.shared?.cleanCache(type: .chat)
    }
}

extension MessageListController {
    
    /**
     Handles the navigation bar click events.
     
     - Parameters:
        - type: The type of navigation bar click event.
        - indexPath: The index path associated with the event (optional).
     */
    @objc open func navigationClick(type: EaseChatNavigationBarClickEvent, indexPath: IndexPath?) {
        switch type {
        case .back: self.pop()
        case .avatar, .title: self.viewDetail()
        case .rightItems: self.rightItemsAction(indexPath: indexPath)
        default:
            break
        }
    }
    
    /**
     This method is called to view the detail of a chat message.
     It determines the type of chat (individual or group) and presents the appropriate view controller accordingly.
     If the previous view controller in the navigation stack is either `GroupInfoViewController` or `ContactInfoViewController`, it pops the current view controller.
     If the chat type is individual, it presents the `ContactInfoController` with the given profile.
     If the chat type is group, it presents the `GroupInfoController` with the given group ID and updates the navigation title with the group name.
     If there is no previous view controller in the navigation stack, it checks if the presenting view controller is either `GroupInfoViewController` or `ContactInfoViewController` and dismisses it.
     If the chat type is individual, it presents the `ContactInfoController` with the given profile.
     If the chat type is group, it presents the `GroupInfoController` with the given group ID and updates the navigation title with the group name.
     */
    @objc open func viewDetail() {
        if let count = self.navigationController?.viewControllers.count {
            if let previous = self.navigationController?.viewControllers[safe: count - 2] {
                if previous is GroupInfoViewController || previous is ContactInfoViewController {
                    self.pop()
                } else {
                    if self.chatType == .chat {
                        let vc = ComponentsRegister.shared.ContactInfoController.init(profile: self.profile)
                        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
                    } else {
                        let vc = ComponentsRegister.shared.GroupInfoController.init(group: self.profile.id) { [weak self] id, name in
                            self?.navigation.title = name
                        }
                        vc.modalPresentationStyle = .fullScreen
                        ControllerStack.toDestination(vc: vc)
                    }
                }
            } else {
                if self.chatType == .chat {
                    let vc = ComponentsRegister.shared.ContactInfoController.init(profile: self.profile)
                    vc.modalPresentationStyle = .fullScreen
                    ControllerStack.toDestination(vc: vc)
                } else {
                    let vc = ComponentsRegister.shared.GroupInfoController.init(group: self.profile.id) { [weak self] id, name in
                        self?.navigation.title = name
                    }
                    vc.modalPresentationStyle = .fullScreen
                    ControllerStack.toDestination(vc: vc)
                }
            }
        } else {
            if let presentingVC = self.presentingViewController {
                if presentingVC is GroupInfoViewController || presentingVC is ContactInfoViewController {
                    presentingVC.dismiss(animated: false)
                } else {
                    if self.chatType == .chat {
                        let vc = ComponentsRegister.shared.ContactInfoController.init(profile: self.profile)
                        vc.modalPresentationStyle = .fullScreen
                        ControllerStack.toDestination(vc: vc)
                    } else {
                        let vc = ComponentsRegister.shared.GroupInfoController.init(group: self.profile.id) { [weak self] id, name in
                            self?.navigation.title = name
                        }
                        vc.modalPresentationStyle = .fullScreen
                        ControllerStack.toDestination(vc: vc)
                    }
                }
            } else {
                if self.chatType == .chat {
                    let vc = ComponentsRegister.shared.ContactInfoController.init(profile: self.profile)
                    vc.modalPresentationStyle = .fullScreen
                    ControllerStack.toDestination(vc: vc)
                } else {
                    let vc = ComponentsRegister.shared.GroupInfoController.init(group: self.profile.id) { [weak self] id, name in
                        self?.navigation.title = name
                    }
                    vc.modalPresentationStyle = .fullScreen
                    ControllerStack.toDestination(vc: vc)
                }
            }
        }
        
    }
    
    @objc open func rightItemsAction(indexPath: IndexPath?) {
//        switch indexPath?.row {
//        case <#pattern#>:
//            <#code#>
//        default:
//            <#code#>
//        }
    }
    
    @objc open func pop() {
        if self.navigationController != nil {
            self.navigationController?.popViewController(animated: true)
        } else {
            self.dismiss(animated: true)
        }
    }

    
    
}

//MARK: - MessageListDriverEventsListener
extension MessageListController: MessageListDriverEventsListener {
    public func onMessageWillSendFillExtensionInfo() -> Dictionary<String, Any> {
        //Insert extension info before sending message.
        [:]
    }
    
    
    /**
     Filters the available message actions based on the provided `ChatMessage`.

     - Parameters:
         - message: The `ChatMessage` object to filter the actions for.

     - Returns: An array of `ActionSheetItemProtocol` representing the filtered message actions.
     */
    @objc open func filterMessageActions(message: ChatMessage) -> [ActionSheetItemProtocol] {
        var messageActions = Appearance.chat.messageLongPressedActions
        if message.body.type != .text {
            messageActions.removeAll { $0.tag == "Copy" }
            messageActions.removeAll { $0.tag == "Edit" }
        } else {
            if message.direction != .send {
                messageActions.removeAll { $0.tag == "Edit" }
            } else {
                if message.status != .succeed {
                    messageActions.removeAll { $0.tag == "Edit" }
                }
            }
        }
        if message.direction != .send {
            messageActions.removeAll { $0.tag == "Recall" }
        } else {
            let duration = UInt(abs(Double(Date().timeIntervalSince1970) - Double(message.timestamp/1000)))
            if duration > Appearance.chat.recallExpiredTime {
                messageActions.removeAll { $0.tag == "Recall" }
            }
        }
        return messageActions
    }
    
    public func onMessageBubbleLongPressed(message: ChatMessage) {
        self.showMessageLongPressedDialog(message: message)
    }
    
    /**
     Shows a long-pressed dialog for a given chat message.
     
     - Parameters:
        - message: The chat message for which the dialog is shown.
     */
    @objc open func showMessageLongPressedDialog(message: ChatMessage) {
        DialogManager.shared.showMessageActions(actions: self.filterMessageActions(message: message)) { [weak self] item in
            self?.processMessage(item: item, message: message)
        }
    }
    
    /**
     Processes a chat message based on the selected action sheet item.
     
     - Parameters:
         - item: The selected action sheet item.
         - message: The chat message to be processed.
     */
    @objc open func processMessage(item: ActionSheetItemProtocol,message: ChatMessage) {
        UIViewController.currentController?.dismiss(animated: true)
        switch item.tag {
        case "Copy":
            self.viewModel.processMessage(operation: .copy, message: message, edit: "")
        case "Edit":
            self.editAction(message: message)
        case "Reply":
            self.viewModel.processMessage(operation: .reply, message: message)
        case "Recall":
            self.viewModel.processMessage(operation: .recall, message: message)
        case "Delete":
            self.viewModel.processMessage(operation: .delete, message: message)
        case "Report":
            self.reportAction(message: message)
        default:
            item.action?(item,message)
            break
        }
    }
    
    /**
        Opens the message editor for editing a chat message.
     
        - Parameters:
            - message: The chat message to be edited.
    */
    @objc open func editAction(message: ChatMessage) {
        if let body = message.body as? ChatTextMessageBody {
            let editor = MessageEditor(content: body.text) { text in
                self.viewModel.processMessage(operation: .edit, message: message, edit: text)
                UIViewController.currentController?.dismiss(animated: true)
            }
            DialogManager.shared.showCustomDialog(customView: editor,dismiss: true)
        }
    }
    
    @objc open func reportAction(message: ChatMessage) {
        DialogManager.shared.showReportDialog(message: message) { error in
            
        }
    }
    
    public func onMessageAttachmentLoading(loading: Bool) {
        self.messageAttachmentLoading(loading: loading)
    }
    
    @objc open func messageAttachmentLoading(loading: Bool) {
        if loading {
            self.loadingView.startAnimating()
        } else {
            self.loadingView.stopAnimating()
        }
    }
    
    public func onMessageBubbleClicked(message: ChatMessage) {
        self.messageBubbleClicked(message: message)
    }
    
    /**
     Handles the click event on a message bubble.
     
     - Parameters:
        - message: The ChatMessage object representing the clicked message.
     */
    @objc open func messageBubbleClicked(message: ChatMessage) {
        switch message.body.type {
        case .file,.video,.image:
            if let body = message.body as? ChatFileMessageBody {
                self.filePath = body.localPath ?? ""
            }
            self.openFile()
        case .custom:
            if let body = message.body as? ChatCustomMessageBody {
                self.viewContact(body: body)
            }
        default:
            break
        }
    }
    
    /**
     Opens the contact view for the given custom message body.
     
     - Parameters:
        - body: The custom message body containing contact information.
     */
    @objc open func viewContact(body: ChatCustomMessageBody) {
        var userId = body.customExt?["userId"] as? String
        if userId == nil {
            userId = body.customExt?["uid"] as? String
        }
        let avatarURL = body.customExt?["avatar"] as? String
        let nickname = body.customExt?["nickname"] as? String
        if body.event == EaseChatUIKit_user_card_message {
            let profile = EaseProfile()
            profile.id = userId ?? ""
            profile.nickname = nickname ?? profile.id
            profile.avatarURL = avatarURL ?? ""
            let vc = ComponentsRegister.shared.ContactInfoController.init(profile: profile)
            vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
        }
    }
    
    public func onMessageAvatarClicked(user: EaseProfileProtocol) {
        self.messageAvatarClick(user: user)
    }
    
    /**
     Handles the click event on the message avatar.
     
     - Parameters:
        - user: The user profile associated with the clicked avatar.
     */
    @objc open func messageAvatarClick(user: EaseProfileProtocol) {
        if user.id == EaseChatUIKitContext.shared?.currentUserId ?? "" {
            return
        }
        let vc = ComponentsRegister.shared.ContactInfoController.init(profile: user)
        vc.modalPresentationStyle = .fullScreen
        ControllerStack.toDestination(vc: vc)
    }
    
    public func onInputBoxEventsOccur(action type: MessageInputBarActionType, attributeText: NSAttributedString?) {
        switch type {
        case .audio: self.audioDialog()
        case .mention:  self.mentionAction()
        case .attachment: self.attachmentDialog()
        default:
            break
        }
    }
    
    /**
     Opens the audio dialog for recording and sending voice messages.
     
     This method stops any currently playing audio, presents a custom audio recording view, and sends the recorded audio message using the view model's `sendMessage` method.
     
     - Note: The audio recording view is an instance of `MessageAudioRecordView` and is presented as a custom dialog using `DialogManager.shared.showCustomDialog`.
     - Note: The recorded audio message is sent as a text message with the file path of the recorded audio and the duration of the recording as extension information.
     */
    @objc open func audioDialog() {
        AudioTools.shared.stopPlaying()
        let audioView = MessageAudioRecordView(frame: CGRect(x: 0, y: 0, width: self.view.frame.width, height: 200)) { [weak self] url, duration in
            UIViewController.currentController?.dismiss(animated: true)
            self?.viewModel.sendMessage(text: url.path, type: .voice, extensionInfo: ["duration":duration])
        } trashClosure: {
            
        }

        DialogManager.shared.showCustomDialog(customView: audioView,dismiss: false)
    }
    
    /**
     Handles the action of mentioning a user in the chat.
     
     This method presents a view controller that allows the user to select a participant to mention in the chat.
     The selected participant's profile ID is used to update the mention IDs in the view model.
     */
    @objc open func mentionAction() {
        let vc = ComponentsRegister.shared.GroupParticipantController.init(groupId: self.profile.id, operation: .mention)
        vc.mentionClosure = { [weak self] in
            self?.viewModel.updateMentionIds(profile: $0, type: .add)
        }
        self.present(vc, animated: true)
    }
    
    /**
     Opens an attachment dialog to allow the user to select an action.
     */
    @objc open func attachmentDialog() {
        DialogManager.shared.showActions(actions: Appearance.chat.inputExtendActions) { [weak self] item in
            self?.handleAttachmentAction(item: item)
        }
    }
    
    @objc open func handleAttachmentAction(item: ActionSheetItemProtocol) {
        switch item.tag {
        case "File": self.selectFile()
        case "Photo": self.selectPhoto()
        case "Camera": self.openCamera()
        case "Contact": self.selectContact()
        default:
            break
        }
    }
    
    /**
     Opens the photo library and allows the user to select a photo.
     
     - Note: This method checks if the photo library is available on the device. If it is not available, an alert is displayed to the user.
     */
    @objc open func selectPhoto() {
        guard UIImagePickerController.isSourceTypeAvailable(.photoLibrary) else {
            DialogManager.shared.showAlert(title: "permissions disable".chat.localize, content: "photo_disable".chat.localize, showCancel: false, showConfirm: true) { _ in
                
            }
            return
        }
        let imagePickerController = UIImagePickerController()
        imagePickerController.delegate = self
        imagePickerController.sourceType = .photoLibrary
        self.present(imagePickerController, animated: true, completion: nil)
    }
    
    @objc open func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DialogManager.shared.showAlert(title: "permissions disable".chat.localize, content: "camera_disable".chat.localize, showCancel: false, showConfirm: true) { _ in
                
            }
            return
        }
        let imagePicker = UIImagePickerController()
        imagePicker.sourceType = .camera
        imagePicker.delegate = self
        imagePicker.mediaTypes = [kUTTypeImage as String, kUTTypeMovie as String]
        imagePicker.videoMaximumDuration = 20
        self.present(imagePicker, animated: true, completion: nil)
    }
    
    /**
     Opens a document picker to allow the user to select a file.
     
     The document picker supports various file types including content, text, source code, images, PDFs, Keynote files, Word documents, Excel spreadsheets, PowerPoint presentations, and generic data files.
     
     - Note: The selected file will be handled by the `UIDocumentPickerDelegate` methods implemented in the `MessageListController`.
     */
    @objc open func selectFile() {
        let documentPicker = UIDocumentPickerViewController(documentTypes: ["public.content", "public.text", "public.source-code", "public.image", "public.jpeg", "public.png", "com.adobe.pdf", "com.apple.keynote.key", "com.microsoft.word.doc", "com.microsoft.excel.xls", "com.microsoft.powerpoint.ppt","public.data"], in: .open)
        documentPicker.delegate = self
        documentPicker.modalPresentationStyle = .fullScreen
        self.present(documentPicker, animated: true, completion: nil)
    }
    
    /**
     Selects a contact and shares their information.

     - Parameters:
         - None

     - Returns: None
     */
    @objc open func selectContact() {
        let vc = ComponentsRegister.shared.ContactsController.init(headerStyle: .shareContact,provider: nil)
        vc.confirmClosure = { profiles in
            vc.dismiss(animated: true) {
                if let user = profiles.first {
                    DialogManager.shared.showAlert(title: "Share Contact".chat.localize, content: "Share Contact".chat.localize+"`\(user.nickname.isEmpty ? user.id:user.nickname)`?", showCancel: true, showConfirm: true) { [weak self] _ in
                        self?.viewModel.sendMessage(text: EaseChatUIKit_user_card_message, type: .contact,extensionInfo: ["uid":user.id,"avatar":user.avatarURL,"nickname":user.nickname])
                    }
                    
                }
            }
        }
        self.present(vc, animated: true)
    }
    
    @objc open func openFile() {
        let previewController = QLPreviewController()
        previewController.dataSource = self
        self.navigationController?.pushViewController(previewController, animated: true)
    }
}

//MARK: - UIImagePickerControllerDelegate&UINavigationControllerDelegate
extension MessageListController:UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        self.processImagePickerData(info: info)
        picker.dismiss(animated: true, completion: nil)
    }
    
    /**
     Processes the data received from the image picker.
     
     - Parameters:
         - info: A dictionary containing the information about the selected media.
     */
    @objc open func processImagePickerData(info: [UIImagePickerController.InfoKey : Any]) {
        let mediaType = info[UIImagePickerController.InfoKey.mediaType] as? String
        if mediaType == kUTTypeMovie as String {
            guard let videoURL = info[.mediaURL] as? URL else { return }
            guard let url = MediaConvertor.videoConvertor(videoURL: videoURL) else { return }
            let fileName = url.lastPathComponent
            let fileURL = URL(fileURLWithPath: MediaConvertor.filePath()+"/\(fileName)")
            if FileManager.default.fileExists(atPath: url.path) {
                do {
                    try Data(contentsOf: url).write(to: fileURL)
                } catch {
                    consoleLogInfo("write video error:\(error.localizedDescription)", type: .error)
                }
            }
            let duration = AVURLAsset(url: fileURL).duration.value
            self.viewModel.sendMessage(text: fileURL.path, type: .video,extensionInfo: ["duration":duration])
        } else {
            if let imageURL = info[.imageURL] as? URL {
                let fileName = imageURL.lastPathComponent
                let fileURL = URL(fileURLWithPath: MediaConvertor.filePath()+"/\(fileName)")
                do {
                    let image = UIImage(contentsOfFile: fileURL.path)?.fixOrientation()
                    try image?.jpegData(compressionQuality: 1)?.write(to: fileURL)
                } catch {
                    consoleLogInfo("write fixOrientation image error:\(error.localizedDescription)", type: .error)
                }
                self.viewModel.sendMessage(text: fileURL.path, type: .image)
            }
        }
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true, completion: nil)
    }
}
//MARK: - UIDocumentPickerDelegate
extension MessageListController: UIDocumentPickerDelegate {
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.documentPickerOpenFile(controller: controller,urls: urls)
        
    }
    
    @objc open func documentPickerOpenFile(controller: UIDocumentPickerViewController,urls: [URL]) {
        if controller.documentPickerMode == UIDocumentPickerMode.open {
            guard let selectedFileURL = urls.first else {
                return
            }
            if selectedFileURL.startAccessingSecurityScopedResource() {
                let fileURL = URL(fileURLWithPath: MediaConvertor.filePath()+"/\(selectedFileURL.lastPathComponent)")
                do {
                    try Data(contentsOf: selectedFileURL).write(to: fileURL)
                } catch {
                    consoleLogInfo("write file error:\(error.localizedDescription)", type: .error)
                }
                self.viewModel.sendMessage(text: fileURL.path, type: .file)
                selectedFileURL.stopAccessingSecurityScopedResource()
            } else {
                DialogManager.shared.showAlert(title: "permissions disable".chat.localize, content: "file_disable".chat.localize, showCancel: false, showConfirm: true) { _ in
                    
                }
            }
        }
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        
    }
    
}

extension MessageListController: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        1
    }
    
    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let fileURL = URL(fileURLWithPath: self.filePath)
        return fileURL as QLPreviewItem
    }
    
    
}
//MARK: - ThemeSwitchProtocol
extension MessageListController: ThemeSwitchProtocol {
    
    public func switchTheme(style: ThemeStyle) {
        self.view.backgroundColor = style == .dark ? UIColor.theme.neutralColor1:UIColor.theme.neutralColor98
        var images = [UIImage(named: "audio_call", in: .chatBundle, with: nil)!,UIImage(named: "video_call", in: .chatBundle, with: nil)!]
        if style == .light {
            images = images.map({ $0.withTintColor(UIColor.theme.neutralColor3) })
        }
        self.navigation.updateRightItems(images: images)
    }
    
}
