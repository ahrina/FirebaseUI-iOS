//
//  Copyright (c) 2016 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import Firebase
import FirebaseDatabaseUI
import FirebaseAuthUI

struct Chat {
  var uid: String
  var name: String
  var text: String
  
  var dictionary: [String: String] {
    return [
      "uid" : self.uid,
      "name": self.name,
      "text": self.text,
    ]
  }
  
  init(uid: String, name: String, text: String) {
    self.name = name; self.uid = uid; self.text = text
  }
  
  init?(snapshot: FIRDataSnapshot) {
    guard let dict = snapshot.value as? [String: String] else { return nil }
    guard let name = dict["name"] else { return nil }
    guard let uid  = dict["uid"]  else { return nil }
    guard let text = dict["text"] else { return nil }
    
    self.name = name
    self.uid = uid
    self.text = text
  }
}

/// View controller demonstrating using a FirebaseCollectionViewDataSource
/// to populate a collection view with chat messages. The relevant code
/// is in the call to `collectionViewDataSource.populateCellWithBlock`.
///
// All of the error handling in this controller is done with `fatalError`;
// please don't copy paste it into your production code.
class ChatViewController: UIViewController, UICollectionViewDelegateFlowLayout {
  
  private static let reuseIdentifier = "ChatCollectionViewCell"
  
  @IBOutlet private var collectionView: UICollectionView!
  @IBOutlet private var textView: UITextView! {
    didSet {
      textView.layer.borderColor = UIColor.grayColor().colorWithAlphaComponent(0.5).CGColor
      textView.layer.borderWidth = 1
      textView.layer.cornerRadius = 8
      textView.layer.masksToBounds = true
    }
  }
  @IBOutlet private var sendButton: UIButton!
  
  // Used to shift view contents up when the keyboard appears.
  @IBOutlet weak var bottomConstraint: NSLayoutConstraint!
  
  private let auth = FIRAuth.auth()
  private let chatReference = FIRDatabase.database().reference().child("chats")
  
  private var collectionViewDataSource: FirebaseCollectionViewDataSource! = nil
  
  private var user: FIRUser?
  private var query: FIRDatabaseQuery?
  
  static func fromStoryboard(storyboard: UIStoryboard = AppDelegate.mainStoryboard) -> ChatViewController {
    return storyboard.instantiateViewControllerWithIdentifier("ChatViewController") as! ChatViewController
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    self.collectionView.backgroundColor = UIColor.whiteColor()
    self.collectionView.delegate = self
    let layout = self.collectionView.collectionViewLayout as! UICollectionViewFlowLayout
    layout.minimumInteritemSpacing = CGFloat.max
    layout.minimumLineSpacing = 4
    
    self.auth?.addAuthStateDidChangeListener { (auth, user) in
      self.user = user
    }
    
    self.sendButton.addTarget(self, action: #selector(didTapSend), forControlEvents: .TouchUpInside)
  }
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    
    self.auth?.signInAnonymouslyWithCompletion { (user, error) in
      if let error = error {
        fatalError("Sign in failed: \(error.localizedDescription)")
      }
      
      self.query = self.chatReference.queryLimitedToLast(50)
      
      self.collectionViewDataSource = FirebaseCollectionViewDataSource(query: self.query!,
        prototypeReuseIdentifier: ChatViewController.reuseIdentifier,
        view: self.collectionView)
      
      // The initializer called above--though it takes a collection view--
      // doesn't actually set the collection view's data source, so if
      // we don't set it before trying to populate our view our app will crash.
      self.collectionView.dataSource = self.collectionViewDataSource
      
      self.collectionViewDataSource.populateCellWithBlock { (anyCell, data) in
        guard let cell = anyCell as? ChatCollectionViewCell else {
          fatalError("Unexpected collection view cell class \(anyCell.self)")
        }
        
        let chat = Chat(snapshot: data as! FIRDataSnapshot)!
        cell.populateCellWithChat(chat, user: self.user, maxWidth: self.view.frame.size.width)
      }
      
      // Unfortunately neither FirebaseArray nor FirebaseCollectionViewDataSource
      // provide an event listener, so in order to scroll on new insertions we
      // still need to use the query directly.
      self.query!.observeEventType(.ChildAdded, withBlock: { [unowned self] _ in
        self.scrollToBottom(animated: true)
      })
    }
    
    // Notification boilerplate to handle keyboard appearance/disappearance
    NSNotificationCenter.defaultCenter().addObserver(self,
                                                     selector: #selector(keyboardWillShow),
                                                     name: UIKeyboardWillShowNotification,
                                                     object: nil)
    NSNotificationCenter.defaultCenter().addObserver(self,
                                                     selector: #selector(keyboardWillHide),
                                                     name: UIKeyboardWillHideNotification,
                                                     object: nil)
  }
  
  // MARK: - Boilerplate
  
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)
    NSNotificationCenter.defaultCenter().removeObserver(self)
  }
  
  @objc private func keyboardWillShow(notification: NSNotification) {
    let userInfo = notification.userInfo!
    let endFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey] as! NSValue
    let endHeight = endFrameValue.CGRectValue().size.height
    
    self.bottomConstraint.constant = endHeight
    
    let curve = UIViewAnimationCurve(rawValue: userInfo[UIKeyboardAnimationCurveUserInfoKey] as! Int)!
    let duration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as! Double
    
    UIView.setAnimationCurve(curve)
    UIView.animateWithDuration(duration) { 
      self.view.layoutIfNeeded()
    }
  }
  
  @objc private func keyboardWillHide(notification: NSNotification) {
    self.bottomConstraint.constant = 6
    
    let userInfo = notification.userInfo!
    let curve = UIViewAnimationCurve(rawValue: userInfo[UIKeyboardAnimationCurveUserInfoKey] as! Int)!
    let duration = userInfo[UIKeyboardAnimationDurationUserInfoKey] as! Double
    
    UIView.setAnimationCurve(curve)
    UIView.animateWithDuration(duration) {
      self.view.layoutIfNeeded()
    }
  }
  
  @objc private func didTapSend(sender: AnyObject) {
    guard let user = self.auth?.currentUser else { return }
    let uid = user.uid
    let name = "User " + (uid as NSString).substringToIndex(6)
    let _text = self.textView.text as String?
    guard let text = _text else { return }
    if (text.isEmpty) { return }
    
    let chat = Chat(uid: uid, name: name, text: text)
    
    self.chatReference.childByAutoId().setValue(chat.dictionary) { (error, dbref) in
      if let error = error {
        fatalError("Failed to write message: \(error.localizedDescription)")
      }
    }
    
    self.textView.text = ""
  }
  
  private func scrollToBottom(animated animated: Bool) {
    let fbarray = self.collectionViewDataSource.array
    let indexPath = NSIndexPath(forRow: Int(fbarray.count()) - 1, inSection: 0)
    self.collectionView.scrollToItemAtIndexPath(indexPath, atScrollPosition: .Bottom, animated: animated)
  }
  
  // MARK UICollectionViewDelegateFlowLayout
  
  func collectionView(collectionView: UICollectionView, layout
    collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
    let heightPadding: CGFloat = 16
    
    let width = self.view.frame.size.width
    let blob = self.collectionViewDataSource.objectAtIndex(UInt(indexPath.row)) as! FIRDataSnapshot
    let text = Chat(snapshot: blob)!.text
    
    let rect = ChatCollectionViewCell.boundingRectForText(text, maxWidth: width)
    
    let height = CGFloat(ceil(Double(rect.size.height))) + heightPadding
    return CGSize(width: width, height: height)
  }
}
