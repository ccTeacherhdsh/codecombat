CocoView = require 'views/core/CocoView'
template = require 'templates/play/level/web-surface-view'

module.exports = class WebSurfaceView extends CocoView
  id: 'web-surface-view'
  template: template

  subscriptions:
    'tome:html-updated': 'onHTMLUpdated'

  initialize: (options) ->
    @goals = (goal for goal in options.goalManager?.goals ? [] when goal.html)
    # Consider https://www.npmjs.com/package/css-select to do this on virtualDOM instead of in iframe on concreteDOM
    super(options)

  afterRender: ->
    super()
    @iframe = @$('iframe')[0]
    $(@iframe).on 'load', (e) =>
      window.addEventListener 'message', @onIframeMessage
      @iframeLoaded = true
      @onIframeLoaded?()
      @onIframeLoaded = null

  # TODO: make clicking Run actually trigger a 'create' update here (for resetting scripts)
        
  onHTMLUpdated: (e) ->
    unless @iframeLoaded
      return @onIframeLoaded = => @onHTMLUpdated e unless @destroyed
    dom = htmlparser2.parseDOM e.html, {}
    body = _.find(dom, name: 'body') ? {name: 'body', attribs: null, children: dom}
    html = _.find(dom, name: 'html') ? {name: 'html', attribs: null, children: [body]}
    # TODO: pull out the actual scripts, styles, and body/elements they are doing so we can merge them with our initial structure on the other side
    virtualDOM = @dekuify html
    messageType = if e.create or not @virtualDOM then 'create' else 'update'
    @iframe.contentWindow.postMessage {type: messageType, dom: virtualDOM, goals: @goals}, '*'
    @virtualDOM = virtualDOM

  dekuify: (elem) ->
    return elem.data if elem.type is 'text'
    return null if elem.type is 'comment'  # TODO: figure out how to make a comment in virtual dom
    unless elem.name
      console.log("Failed to dekuify", elem)
      return elem.type
    deku.element(elem.name, elem.attribs, (@dekuify(c) for c in elem.children ? []))

  onIframeMessage: (event) =>
    origin = event.origin or event.originalEvent.origin
    unless origin is window.location.origin
      return console.log 'Ignoring message from bad origin:', origin
    unless event.source is @iframe.contentWindow
      return console.log 'Ignoring message from somewhere other than our iframe:', event.source
    switch event.data.type
      when 'goals-updated'
        Backbone.Mediator.publish 'god:new-html-goal-states', goalStates: event.data.goalStates, overallStatus: event.data.overallStatus
      else
        console.warn 'Unknown message type', event.data.type, 'for message', e, 'from origin', origin

  destroy: ->
    window.removeEventListener 'message', @onIframeMessage
    super()