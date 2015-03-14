//
//  TicketsViewController.swift
//  triage
//
//  Created by Christopher Kintner on 3/4/15.
//  Copyright (c) 2015 Christopher Kintner. All rights reserved.
//

import UIKit

let kViewID = 47205968
let kAssignToTier1MacroID = 47314978
let kAssignToTrashAgent = 47314477

class TicketsViewController: UIViewController {

  private let API = ZendeskAPI.instance
  private let userCache = UserCache()

  private var page: Int = 1

  // XXX - Change to enum for state
  private var isExhausted: Bool = false
  private var isFetching: Bool = false
  private var isRefreshing: Bool = false
  private let emptyDataSource =  EmptyTableViewSource()
  private let loadingDataSource = LoadingTableViewSource()
  private let initialTableViewRowHeight = CGFloat(90)
  private var flag = false
  private var selectedRowIndex: NSIndexPath = NSIndexPath(forRow: -1, inSection: 0)
  private var expanded: Bool = false
  private var offset: CGFloat!
  var macros: [Macro] = []
  var rows: [TicketFilterRow] = []

  private var parameters: NSMutableDictionary {
    get {
      return [
        "per_page": 30,
        "page": self.page + 1,
        "sort_order": "desc",
        "group_by": "+",
        "include": "via_id"
      ]
    }
  }

  @IBOutlet weak var ticketsTableView: UITableView!

  @IBOutlet weak var topConstraint: NSLayoutConstraint!
  lazy private var activityIndicator: UIActivityIndicatorView =
    UIActivityIndicatorView(activityIndicatorStyle: .Gray)
  lazy private var refreshControl: UIRefreshControl = UIRefreshControl()

  override func viewDidLoad() {
    super.viewDidLoad()

    ticketsTableView.rowHeight = initialTableViewRowHeight
    ticketsTableView.estimatedRowHeight = initialTableViewRowHeight//44
    ticketsTableView.delegate = self
    ticketsTableView.dataSource = loadingDataSource
    ticketsTableView.layoutMargins = UIEdgeInsetsZero
    ticketsTableView.separatorInset = UIEdgeInsetsZero

    activityIndicator.frame = CGRectMake(
      0,
      0,
      ticketsTableView.bounds.width,
      44
    )
    ticketsTableView.tableFooterView = activityIndicator
    ticketsTableView.insertSubview(refreshControl, atIndex: 0)

    refreshControl.addTarget(
      self,
      action: "willRefresh:",
      forControlEvents: .ValueChanged
    )
    
    configureNavBar()

    activityIndicator.startAnimating()

    fetchMacros()
    fetchTicketRows(page: 1)
  }
  
  func configureNavBar() {
    var logoutButton = UIBarButtonItem(title: "Logout", style: UIBarButtonItemStyle.Plain, target: self, action: "doLogout")
    self.navigationItem.leftBarButtonItem = logoutButton
    
    var title = UILabel()
    title.text = "Z1 Triage"
    title.textColor = Colors.ZendeskGreen
    title.font = UIFont.boldSystemFontOfSize(20)
    title.frame = CGRectMake(0, 0, 100, 30);
    title.textAlignment = NSTextAlignment.Center
    self.navigationItem.titleView = title
    
    //self.followScrollView(ticketsTableView, usingTopConstraint: topConstraint, withDelay: 65)
    //self.setShouldScrollWhenContentFits(true)
    navigationController?.navigationBar.translucent = false
    navigationController?.navigationBar.tintColor = Colors.ZendeskGreen
  }
  
  func doLogout() {
    NSNotificationCenter.defaultCenter().postNotificationName(LogoutNotification, object: self)
  }
  
  func configureTableView() {
    if rows.count > 0 {
      ticketsTableView.dataSource = self
      ticketsTableView.rowHeight = UITableViewAutomaticDimension
    } else if isFetching || isRefreshing {
      ticketsTableView.rowHeight = initialTableViewRowHeight
      ticketsTableView.dataSource = loadingDataSource
    } else {
      ticketsTableView.rowHeight = initialTableViewRowHeight
      ticketsTableView.dataSource = emptyDataSource
    }
    
    ticketsTableView.reloadData()
  }

  func fetchMacros() {
    API.getMacros(success: didFetchMacros, failure: nil)
  }

  func fetchTicketRows(#page: Int?) {
    if (isFetching) {
      return
    }

    var params: NSMutableDictionary = parameters

    isFetching = true

    if page != nil {
      params["page"] = page!
    } else {
      self.page = params["page"] as Int
    }

    API.executeView(
      kViewID,
      parameters: params,
      success: didFetchTicketRows,
      failure: didError
    )
  }

  func didFetchMacros(operation: AFHTTPRequestOperation!, macros: [Macro]) {
    self.macros = macros
  }

  func didFetchTicketRows(operation: AFHTTPRequestOperation!, rows: [TicketFilterRow]) {

    if (rows.count == 0) {
      isExhausted = true
    }
    
    loadRequesters(rows)

    if (isRefreshing) {
      self.rows = rows
    } else {
      self.rows += rows
    }
    
    isFetching = false
    isRefreshing = false
    
    configureTableView()
    
    activityIndicator.stopAnimating()
    refreshControl.endRefreshing()
  }
  
  func loadRequesters(rows: [TicketFilterRow]) {
    var ticketsNeedingRequester = [TicketFilterRow]()
    var userIdsToFetch = [Int: AnyObject]() // hash as set
    
    for ticketRow in rows {
      if ticketRow.ticket.requester == nil {
        if let cachedUser = userCache.lookupUserByUserId(ticketRow.requester_id) {
          var ticket = ticketRow.fields.ticket
          ticket.requester = cachedUser
        } else {
          ticketsNeedingRequester.append(ticketRow)
          userIdsToFetch[ticketRow.requester_id] = 1
        }
      }
    }
    

    API.getManyUsers(userIdsToFetch.keys.array, success: { (operation: AFHTTPRequestOperation!, users: [User]) -> Void in
      
      for ticketRow in ticketsNeedingRequester {
        var match = users.filter({$0.fields.id == ticketRow.requester_id})
        if match.count > 0 {
          var fields = ticketRow.fields
          var ticket = fields.ticket
          ticket.requester = match[0]
          
          ticketRow.fields = TicketFilterRowFields(requester_id: fields.requester_id, ticket: ticket)
          
        }
      }
      
      self.ticketsTableView.reloadData()
      }, failure: didError)
  }

  func didError(operation: AFHTTPRequestOperation!, error: NSError) {
    activityIndicator.stopAnimating()
    refreshControl.endRefreshing()
    isFetching = false
    isRefreshing = false
  }

  func willRefresh(sender: UIRefreshControl) {
    sender.beginRefreshing()
    isRefreshing = true
    configureTableView()
    fetchTicketRows(page: 1)
  }
  
  func loadMoreTicketsIfNeeded() {
    if isFetching || isExhausted {
      return
    }
    
    let tableHeight = ticketsTableView.frame.height
    let offset = ticketsTableView.contentOffset.y + tableHeight
    let limit = ticketsTableView.contentSize.height - 300
  
    if (offset > limit) {
      println("running low of tickets - loading more")
      fetchTicketRows(page: nil)
    }
  }

  func scrollViewDidScroll(scrollView: UIScrollView) {
    loadMoreTicketsIfNeeded()
  }
}

extension TicketsViewController: UITableViewDelegate {

  
  
}

extension TicketsViewController: UITableViewDataSource{
    
  func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let row = rows[indexPath.row]
    
    if (indexPath.row == self.selectedRowIndex.row){
        let cell = ticketsTableView.dequeueReusableCellWithIdentifier(
            "DetailTableViewCell", forIndexPath: indexPath
            ) as DetailTableViewCell
        
        cell.layoutMargins = UIEdgeInsetsZero
        cell.ticket = row.ticket
        cell.delegate = self
        cell.updateConstraintsIfNeeded()
        return cell
    }
    
    let cell = ticketsTableView.dequeueReusableCellWithIdentifier(
      "TicketTableViewCell", forIndexPath: indexPath
    ) as TicketTableViewCell

    cell.layoutMargins = UIEdgeInsetsZero
    cell.ticket = row.ticket
    cell.delegate = self
    cell.updateConstraintsIfNeeded()

    return cell
  }
  
  func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return rows.count
  }
    
  func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    selectedRowIndex = indexPath
    expanded = true
    
    offset = tableView.contentOffset.y
    var cellRect = tableView.rectForRowAtIndexPath(indexPath)

    self.navigationController?.setNavigationBarHidden(true, animated: false)
    UIView.animateWithDuration(0.3, animations: { () -> Void in
        tableView.contentOffset = CGPoint(x: 0, y: cellRect.minY)
    })
    tableView.beginUpdates()
    tableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
    tableView.endUpdates()
  }
  func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
    if indexPath.row == selectedRowIndex.row {
        return UITableViewAutomaticDimension > self.view.bounds.height ? UITableViewAutomaticDimension: self.view.bounds.height
    }else {
      return initialTableViewRowHeight
    }
  }
}

extension TicketsViewController: TicketTableViewCellDelegate, DetailTableViewCellDelegate {
  
  func didFarRightSwipe(cell: TicketTableViewCell) {
    println("didFarRightSwipe")
    let viewController =
      storyboard?.instantiateViewControllerWithIdentifier("MacrosViewController") as MacrosViewController

    viewController.transitioningDelegate = viewController
    viewController.macros = macros
    viewController.modalPresentationStyle = .Custom

    presentViewController(viewController, animated: true, completion: nil)
  }

  func didNearRightSwipe(cell: TicketTableViewCell) {
    let indexPath = ticketsTableView.indexPathForCell(cell)!
    
    loadMoreTicketsIfNeeded() // this needs to be before we remove the cell since the contentsize.height is wrong afterwards
    rows.removeAtIndex(indexPath.row)
    ticketsTableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Right)
    
    API.applyMacroToTicket(
      kAssignToTier1MacroID,
      ticketID: cell.ticket!.id,
      success: { (operation: AFHTTPRequestOperation!, result: MacroResult) -> Void in
        let ticket = result.ticket

        cell.ticket = ticket

        ticket.save(success: nil, failure: nil)
      },
      failure: nil
    )
    println("didNearRightSwipe")
  }

  func didLeftSwipe(cell: TicketTableViewCell) {
    let indexPath = ticketsTableView.indexPathForCell(cell)!

    loadMoreTicketsIfNeeded() // this needs to be before we remove the cell since the contentsize.height is wrong afterwards
    rows.removeAtIndex(indexPath.row)
    ticketsTableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Left)
    

    API.applyMacroToTicket(
      kAssignToTrashAgent,
      ticketID: cell.ticket!.id,
      success: { (operation: AFHTTPRequestOperation!, result: MacroResult) -> Void in
        let ticket = result.ticket

        cell.ticket = ticket

        ticket.save(success: nil, failure: nil)
      },
      failure: nil
    )
    println("didLeftSwipe")
  }
    
  func didTap(cell: TicketTableViewCell){
    println("didTap")
    
    let viewController =
    storyboard?.instantiateViewControllerWithIdentifier("DetailViewController") as DetailViewController
    
    viewController.ticket = cell.ticket
    
    viewController.transitioningDelegate = viewController
    viewController.modalPresentationStyle = .Custom
    presentViewController(viewController, animated: true, completion: nil)
  }
    
  func onCancelbutton(cell: DetailTableViewCell) {
    print("onCancelButton")
    self.expanded = false
    self.selectedRowIndex = NSIndexPath(forRow: -1, inSection: 0)
    let indexPath = ticketsTableView.indexPathForCell(cell)!

    println(self.offset)
    println("new\(ticketsTableView.contentOffset.y)")
    UIView.animateWithDuration(0.3, animations: { () -> Void in
        self.ticketsTableView.contentOffset = CGPoint(x: 0, y: self.offset)
        
    })
    println("should be\(ticketsTableView.contentOffset.y)")
 
    self.navigationController?.setNavigationBarHidden(false, animated: false)
    self.ticketsTableView.beginUpdates()
    self.ticketsTableView.reloadRowsAtIndexPaths([indexPath], withRowAnimation: .None)
    self.ticketsTableView.endUpdates()
  }
}
