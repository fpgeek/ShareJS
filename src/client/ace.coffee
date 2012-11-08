# This is some utility code to connect an ace editor to a sharejs document.

Range = ace.require("ace/range").Range

getStartOffsetPosition = (editorDoc, range) ->
  # This is quite inefficient - getLines makes a copy of the entire
  # lines array in the document. It would be nice if we could just
  # access them directly.
  lines = editorDoc.getLines 0, range.start.row
    
  offset = 0

  for line, i in lines
    offset += if i < range.start.row
      line.length
    else
      range.start.column

  # Add the row number to include newlines.
  offset + range.start.row

# Horribly inefficient.
offsetToPos = (editorDoc, offset) ->
  # Again, very inefficient.
  lines = editorDoc.getAllLines()

  row = 0
  for line, row in lines
    break if offset <= line.length

    # +1 for the newline.
    offset -= lines[row].length + 1

  row:row, column:offset

# Convert an ace delta into an op understood by share.js
applyToShareJS = (editorDoc, delta, doc) ->
  # Get the start position of the range, in no. of characters

  pos = getStartOffsetPosition editorDoc, delta.range

  switch delta.action
    when 'insertText' then doc.insert pos, delta.text
    when 'removeText' then doc.del pos, delta.text.length
    
    when 'insertLines'
      text = delta.lines.join('\n') + '\n'
      doc.insert pos, text
      
    when 'removeLines'
      text = delta.lines.join('\n') + '\n'
      doc.del pos, text.length

    else throw new Error "unknown action: #{delta.action}"
  
  return

randomUserId = (length) ->
  length = 10 if not length
  chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-="
  name = (chars[Math.floor (Math.random() * chars.length)] for idx in [0...length])
  name.join('')

cursorColors = ['yellow', 'red', 'blue']
$cursorDoc = {}

cursorInsertListener = (pos, text) ->
  $cursorDoc.jsonText = text
  jsonData = eval('(' + text + ')')
  rmUserId = jsonData.u
  #return if rmUserId is $cursorDoc.userid
  position = jsonData.p
  remoteMarkers = $cursorDoc.remoteMarkers

  editor = $cursorDoc.editor
  editorDoc = editor.getSession().getDocument()
  range = Range.fromPoints offsetToPos(editorDoc, position), offsetToPos(editorDoc, position + 1)

  if remoteMarkers.hasOwnProperty(rmUserId)
    colorClazz = $cursorDoc.remoteMarkers[rmUserId].clazz
    markerId = $cursorDoc.remoteMarkers[rmUserId].id
    editor.getSession().removeMarker markerId
    markerId = editor.getSession().addMarker range, 'ace_marker ' + colorClazz, 'text', true
    $cursorDoc.remoteMarkers[rmUserId] = {'id':markerId, 'clazz':colorClazz}
  else
    colorClazz = cursorColors[$cursorDoc.cursorColorIdx]
    $cursorDoc.cursorColorIdx++
    markerId = editor.getSession().addMarker range, 'ace_marker ' + colorClazz, 'text', true
    $cursorDoc.remoteMarkers[rmUserId] = {'id':markerId, 'clazz':colorClazz}

window.sharejs.extendDoc 'attach_remotecursor', (editor) ->
  $cursorDoc = this
  $cursorDoc.editor = editor
  $cursorDoc.remoteMarkers = {}
  $cursorDoc.cursorColorIdx = 0
  $cursorDoc.userid = randomUserId()
  $cursorDoc.jsonText = ''
  $cursorDoc.on 'insert', cursorInsertListener

# Attach an ace editor to the document. The editor's contents are replaced
# with the document's contents unless keepEditorContents is true. (In which case the document's
# contents are nuked and replaced with the editor's).
window.sharejs.extendDoc 'attach_ace', (editor, keepEditorContents) ->
  throw new Error 'Only text documents can be attached to ace' unless @provides['text']

  doc = this
  editorDoc = editor.getSession().getDocument()
  editorDoc.setNewLineMode 'unix'

  check = ->
    window.setTimeout ->
        editorText = editorDoc.getValue()
        otText = doc.getText()

        if editorText != otText
          console.error "Text does not match!"
          console.error "editor: #{editorText}"
          console.error "ot:     #{otText}"
          # Should probably also replace the editor text with the doc snapshot.
      , 0

  if keepEditorContents
    doc.del 0, doc.getText().length
    doc.insert 0, editorDoc.getValue()
  else
    editorDoc.setValue doc.getText()

  check()

  # When we apply ops from sharejs, ace emits edit events. We need to ignore those
  # to prevent an infinite typing loop.
  suppress = false
  
  # Listen for edits in ace
  editorListener = (change) ->
    return if suppress
    applyToShareJS editorDoc, change.data, doc

    check()

  editorDoc.on 'change', editorListener

  # Listen for remote ops on the sharejs document
  docListener = (op) ->
    suppress = true
    applyToDoc editorDoc, op
    suppress = false

    check()

  changeSelectionListener = (op) ->
    #$cursorDoc.insert getStartOffsetPosition editorDoc, editor.getSelectionRange(), $cursorDoc.userid
    pos = getStartOffsetPosition editorDoc, editor.getSelectionRange()
    jsonStr = '{p:' + pos + ', u:' + '"' + $cursorDoc.userid + '"' + '}'
    op = [{i:jsonStr, p:0}, {d:jsonStr, p:0}]
    $cursorDoc.submitOp op

  editor.on 'changeSelection', changeSelectionListener

  doc.on 'insert', (pos, text) ->
    suppress = true
    editorDoc.insert offsetToPos(editorDoc, pos), text
    cursorInsertListener 0, $cursorDoc.jsonText
    suppress = false
    check()

  doc.on 'delete', (pos, text) ->
    suppress = true
    range = Range.fromPoints offsetToPos(editorDoc, pos), offsetToPos(editorDoc, pos + text.length)
    editorDoc.remove range
    suppress = false
    check()

  doc.detach_ace = ->
    doc.removeListener 'remoteop', docListener
    editorDoc.removeListener 'change', editorListener
    delete doc.detach_ace

  return

