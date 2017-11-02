# coding: utf-8
import re
import sys

state = dict()
code = dict()
tMin = 1
t = tMin-1

if len(sys.argv) != 2:
	print "usage: script.py trace_filename"
	exit(1)

with open(sys.argv[1]) as f:
	data = f
	for line in data:
		line = line.strip()
		if line.startswith('trace'):
			elems = line.split('/')
			if elems[1] == 'state':
				tmp = dict()
				for i in range(2, len(elems)):
					register, _, content = elems[i].partition(':')
					tmp[register] = content
				state[t] = tmp
			elif elems[1] == 'instruction':
				code[elems[2]] = elems[3]
				t += 1
	# Get back to a valid final state
	while t not in state or state[t] == {}:
		t -= 1
	tMax = t
	print state[tMax]

def htoi(h):
	return int(h, 16)

def itoh4(i):
	return '%0.4X' % i

pcMin = htoi(min(code.keys()))
pcMax = htoi(max(code.keys()))

def prevInstAddr(addr, count=1):
	nextAddr = addr-1
	while count>0 and nextAddr>=pcMin and nextAddr<=pcMax:
		if itoh4(nextAddr) in code:
			addr = nextAddr
			count -= 1
		nextAddr -= 1
	return addr

def nextInstAddr(addr, count=1):
	nextAddr = addr+1
	while count>0 and nextAddr>=pcMin and nextAddr<=pcMax:
		if itoh4(nextAddr) in code:
			addr = nextAddr
			count -= 1
		nextAddr += 1
	return addr

print '\n'*80

breakpoints = set()

t = tMin
winPos = None
winSize = 40 # At least 5
winBorderSize = 1
reverse = False
while True:
	# --- printing ---

	print '\n'*80
	print '  |  '.join(map('='.join, sorted(state[t].items())))
	print

	pc = state[t]['pc']

	if winPos == None:
		winPos = prevInstAddr(htoi(pc), winBorderSize)
	else:
		winEndPos = nextInstAddr(winPos, (winSize-winBorderSize)-1)
		if htoi(pc) < winPos or winEndPos < htoi(pc):
			winPos = prevInstAddr(htoi(pc), winBorderSize)

	addr = winPos
	for i in range(winSize):
		if addr <= pcMax:
			breakInfo = '●' if itoh4(addr) in breakpoints else ' '
			cursorInfo = '>' if itoh4(addr) == pc else ' '
			print '%s%s %s: %s' % (breakInfo, cursorInfo, itoh4(addr), code[itoh4(addr)])
			if addr != pcMax:
				addr = nextInstAddr(addr)
			else:
				addr = 0xFFFF
		else:
			print '   XXXX: --'

	# --- inputs ---

	while True:
		userInput = raw_input()
		if userInput == 'q':
			exit(0)
		if userInput == 'start':
			t = tMin
			break
		if userInput == '':
			if reverse:
				t = max(t-1, tMin)
			else:
				t = min(t+1, tMax)
			break
		if userInput in ('n', '+', ''):
			t = min(t+1, tMax)
			break
		if userInput in ('rn', '-'):
			t = max(t-1, tMin)
			break
		if userInput in ('s', '++'):
			stoppoint = itoh4(nextInstAddr(htoi(pc)))
			t = min(t+1, tMax)
			while True:
				pc = state[t]['pc']
				if pc in breakpoints or t == tMax or pc == stoppoint:
					break
				t = t+1
			break
		if userInput in ('rs', '--'):
			stoppoint = itoh4(prevInstAddr(htoi(pc)))
			t = max(t-1, tMin)
			while True:
				pc = state[t]['pc']
				if pc in breakpoints or t == tMin or pc == stoppoint:
					break
				t = t-1
			break
		if userInput in ('r', 'reverse'):
			reverse = not reverse
			break
		m = re.match(r'(?:c|continue)(?:\s+([a-zA-Z0-9]{3,4}))?', userInput)
		if m:
			stoppoint = None
			if m.group(1):
				stoppoint = itoh4(htoi(m.group(1)))
			t = min(t+1, tMax)
			while True:
				pc = state[t]['pc']
				if pc in breakpoints or t == tMax or pc == stoppoint:
					break
				t = t+1
			break
		m = re.match(r'(?:rc|rcontinue)(?:\s+([a-zA-Z0-9]{3,4}))?', userInput)
		if m:
			stoppoint = None
			if m.group(1):
				stoppoint = itoh4(htoi(m.group(1)))
			t = max(t-1, tMin)
			while True:
				pc = state[t]['pc']
				if pc in breakpoints or t == tMin or pc == stoppoint:
					break
				t = t-1
			break
		m = re.match(r'(?:rc|rcontinue)(?:\s+([a-zA-Z0-9]{3,4}))?', userInput)
		if m:
			stoppoint = None
			if m.group(1):
				stoppoint = itoh4(htoi(m.group(1)))
			t = max(t-1, tMin)
			while True:
				pc = state[t]['pc']
				if pc in breakpoints or t == tMin or pc == stoppoint:
					break
				t = t-1
			break
# Should count call
#		if userInput in ('ret'):
#			t = min(t+1, tMax)
#			while True:
#				pc = state[t]['pc']
#				if pc in breakpoints or t == tMax or code[pc].startswith('RET'):
#					break
#				t = t+1
#			break
		m = re.match(r'(?:b|br|break)\s+([a-zA-Z0-9]{3,4})', userInput)
		if m:
			breakpoints.add(itoh4(htoi(m.group(1))))
			break
		m = re.match(r'(?:rb|rbr|rbreak)\s+([a-zA-Z0-9]{3,4})', userInput)
		if m:
			breakpoints.remove(itoh4(htoi(m.group(1))))
			break
		print 'Bad command'
