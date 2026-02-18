package memo

Node :: struct {
	key:      Key,
	max:      int,
	interval: ^LazyInterval,
	tstamp:   u64, // timestamp to determine which shifts to apply
	tree:     ^Tree,

	// height counts nodes (not edges)
	height:   int,
	left:     ^Node,
	right:    ^Node,
}

// Adds a new node
node_add :: proc(
	n: ^Node,
	tree: ^Tree,
	key: Key,
	value: ^Interval,
) -> (
	^Node,
	^LazyInterval,
) {
	if n == nil {
		nn := new(Node)
		nn.key = key
		nn.max = value.high
		nn.tstamp = tree.tstamp
		nn.tree = tree
		nn.height = 1
		intervals := make([dynamic]^Interval)
		append(&intervals, value)
		li := new(LazyInterval)
		li.ins = intervals
		li.n = nn
		nn.interval = li
		return nn, nn.interval
	}
	node_apply_shifts(n)

	loc: ^LazyInterval
	if key_compare(key, n.key) < 0 {
		n.left, loc = node_add(n.left, tree, key, value)
	} else if key_compare(key, n.key) > 0 {
		n.right, loc = node_add(n.right, tree, key, value)
	} else {
		// if same key exists update value
		append(&n.interval.ins, value)
		n.tstamp = tree.tstamp
		loc = n.interval
	}
	return node_rebalance_tree(n), loc
}

node_update_max :: proc(n: ^Node) {
	if n != nil {
		if n.right != nil {
			n.max = max(n.max, n.right.max)
		}
		if n.left != nil {
			n.max = max(n.max, n.left.max)
		}
		n.max = max(n.max, lazy_interval_high(n.interval))
	}
}

// Removes a node
node_remove :: proc(n: ^Node, key: Key) -> ^Node {
	if n == nil {
		return nil
	}
	node_apply_shifts(n)
	if key_compare(key, n.key) < 0 {
		n.left = node_remove(n.left, key)
	} else if key_compare(key, n.key) > 0 {
		n.right = node_remove(n.right, key)
	} else {
		if n.left != nil && n.right != nil {
			node_apply_shifts(n.left)
			node_apply_shifts(n.right)
			// node to delete found with both children;
			// replace values with smallest node of the right sub-tree
			rightMinNode := node_find_smallest(n.right)

			n.key = rightMinNode.key
			append(&n.interval.ins, ..rightMinNode.interval.ins[:])
			n.interval.n = n
			n.tstamp = rightMinNode.tstamp
			// delete smallest node that we replaced
			n.right = node_remove(n.right, rightMinNode.key)
		} else if n.left != nil {
			node_apply_shifts(n.left)
			// node only has left child
			return node_rebalance_tree(n.left)
		} else if n.right != nil {
			node_apply_shifts(n.right)
			// node only has right child
			return node_rebalance_tree(n.right)
		} else {
			// node has no children
			return nil
		}
	}
	return node_rebalance_tree(n)
}

// Searches for a node
node_search :: proc(n: ^Node, key: Key) -> ^Node {
	if n == nil {
		return nil
	}
	node_apply_shifts(n)
	if key_compare(key, n.key) < 0 {
		return node_search(n.left, key)
	} else if key_compare(key, n.key) > 0 {
		return node_search(n.right, key)
	} else {
		return n
	}
}

node_remove_overlaps :: proc(n: ^Node, low, high: int) -> ^Node {
	if n == nil {
		return n
	}

	node_apply_shifts(n)

	if low > n.max {
		return n
	}

	n.left = node_remove_overlaps(n.left, low, high)

	for i := 0; i < len(n.interval.ins); {
		if interval_overlaps(n.interval.ins[i]^, low, high) {
			n.interval.ins[i] = n.interval.ins[len(n.interval.ins) - 1]
			new_interval := make([dynamic]^Interval, 0, len(n.interval.ins) - 1)
			append(&new_interval, ..n.interval.ins[:len(n.interval.ins) - 1])
			n.interval.ins = new_interval
		} else {
			i += 1
		}
	}

	if len(n.interval.ins) == 0 {
		doright := high >= n.key.pos
		n := node_remove(n, n.key)
		if doright {
			return node_remove_overlaps(n, low, high)
		}
		return n
	}

	if high < n.key.pos {
		return n
	}
	n.right = node_remove_overlaps(n.right, low, high)
	return n
}

node_allvals :: proc(n: ^Node, acc: ^[dynamic]^Entry) {
	if n == nil {
		return
	}

	node_allvals(n.left, acc)

	for ins in n.interval.ins {
		append(acc, &ins.value)
	}

	node_allvals(n.right, acc)
}

node_get_height :: proc(n: ^Node) -> int {
	if n == nil {
		return 0
	}
	return n.height
}

node_size :: proc(n: ^Node) -> int {
	if n == nil {
		return 0
	}
	return node_size(n.left) + node_size(n.right) + 1
}

node_recalculate_height :: proc(n: ^Node) {
	n.height = 1 + max(node_get_height(n.left), node_get_height(n.right))
}

// Checks if node is balanced and rebalance
node_rebalance_tree :: proc(n: ^Node) -> ^Node {
	if n == nil {
		return n
	}
	node_recalculate_height(n)
	node_update_max(n)

	// check balance factor and rotateLeft if right-heavy and rotateRight if left-heavy
	balanceFactor := node_get_height(n.left) - node_get_height(n.right)
	if balanceFactor <= -2 {
		// check if child is left-heavy and rotateRight first
		if node_get_height(n.right.left) > node_get_height(n.right.right) {
			n.right = node_rotate_right(n.right)
		}
		return node_rotate_left(n)
	} else if balanceFactor >= 2 {
		// check if child is right-heavy and rotateLeft first
		if node_get_height(n.left.right) > node_get_height(n.left.left) {
			n.left = node_rotate_left(n.left)
		}
		return node_rotate_right(n)
	}
	return n
}

// Rotate nodes left to balance node
node_rotate_left :: proc(n: ^Node) -> ^Node {
	node_apply_shifts(n)
	if n.right != nil {
		node_apply_shifts(n.right)
	}

	newRoot := n.right
	n.right = newRoot.left
	newRoot.left = n

	node_recalculate_height(n)
	node_update_max(n)
	node_recalculate_height(newRoot)
	node_update_max(newRoot)
	return newRoot
}

// Rotate nodes right to balance node
node_rotate_right :: proc(n: ^Node) -> ^Node {
	node_apply_shifts(n)
	if n.left != nil {
		node_apply_shifts(n.left)
	}

	newRoot := n.left
	n.left = newRoot.right
	newRoot.right = n

	node_recalculate_height(n)
	node_update_max(n)
	node_recalculate_height(newRoot)
	node_update_max(newRoot)
	return newRoot
}

// Finds the smallest child (based on the key) for the current node
node_find_smallest :: proc(n: ^Node) -> ^Node {
	if n.left != nil {
		node_apply_shifts(n.left)
		return node_find_smallest(n.left)
	} else {
		return n
	}
}

node_apply_shift :: proc(n: ^Node, s: ^Shift) {
	if n.tstamp >= s.tstamp {
		// this shift is outdated and we have already applied it
		return
	}

	n.tstamp = s.tstamp
	if n.max < s.idx {
		return
	}
	n.max += s.amt
	if n.key.pos >= s.idx {
		n.key.pos += s.amt
		lazy_interval_shift(n.interval, s.amt)
	}
	node_update_max(n)
}

node_apply_shifts :: proc(n: ^Node) {
	// optimization: first check if we are completely up-to-date and if so
	// there is nothing to do.
	if len(n.tree.shifts) == 0 ||
	   n.tstamp >= n.tree.shifts[len(n.tree.shifts) - 1].tstamp {
		return
	}
	// optimization: search backwards to find the starting point. Alternatively
	// we could binary search? not sure which is faster.
	j: int
	for j = len(n.tree.shifts) - 1; j > 0; j -= 1 {
		if n.tstamp >= n.tree.shifts[j].tstamp {
			j = j + 1
			break
		}
	}
	for s in n.tree.shifts[j:] {
		s := s
		node_apply_shift(n, &s)
	}
}

node_apply_all_shifts :: proc(n: ^Node) {
	if n == nil {
		return
	}

	node_apply_all_shifts(n.left)
	node_apply_all_shifts(n.right)
	node_apply_shifts(n)
}

node_each_node :: proc(n: ^Node, fn: proc(_: ^Node)) {
	if n == nil {
		return
	}

	node_each_node(n.left, fn)
	node_apply_shifts(n)
	fn(n)
	node_each_node(n.right, fn)
}
