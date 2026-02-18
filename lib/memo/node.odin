package memo

import "core:fmt"
import "core:mem/virtual"
import "core:testing"

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

// --- Tests ---

// Helper: create a fresh Tree for node-level tests.
make_test_tree :: proc() -> ^Tree {
	t := new(Tree)
	return t
}

// Helper: add a node with given key pos, id, and interval high value.
add_test_node :: proc(root: ^Node, tree: ^Tree, pos, id, high: int) -> (^Node, ^LazyInterval) {
	iv := new(Interval)
	iv.low = pos
	iv.high = high
	iv.value = Entry{length = high - pos, examined = high - pos, count = 1}
	return node_add(root, tree, Key{pos, id}, iv)
}

@(test)
test_node_add_and_search :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	// Add three nodes
	root, _ = add_test_node(root, tree, 10, 1, 15)
	root, _ = add_test_node(root, tree, 5, 2, 8)
	root, _ = add_test_node(root, tree, 20, 3, 25)

	// Search for each
	n1 := node_search(root, Key{10, 1})
	testing.expect(t, n1 != nil, "should find node at key {10, 1}")
	testing.expect(t, n1.key.pos == 10, fmt.tprintf("expected pos=10, got %d", n1.key.pos))

	n2 := node_search(root, Key{5, 2})
	testing.expect(t, n2 != nil, "should find node at key {5, 2}")

	n3 := node_search(root, Key{20, 3})
	testing.expect(t, n3 != nil, "should find node at key {20, 3}")

	// Search miss
	miss := node_search(root, Key{99, 99})
	testing.expect(t, miss == nil, "should not find non-existent key")
}

@(test)
test_node_remove :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	root, _ = add_test_node(root, tree, 10, 1, 15)
	root, _ = add_test_node(root, tree, 5, 2, 8)
	root, _ = add_test_node(root, tree, 20, 3, 25)
	root, _ = add_test_node(root, tree, 3, 4, 4)
	root, _ = add_test_node(root, tree, 7, 5, 9)

	testing.expect(t, node_size(root) == 5, fmt.tprintf("expected size 5, got %d", node_size(root)))

	// Remove leaf node
	root = node_remove(root, Key{3, 4})
	testing.expect(t, node_search(root, Key{3, 4}) == nil, "key {3,4} should be removed")
	testing.expect(t, node_size(root) == 4, fmt.tprintf("expected size 4 after remove, got %d", node_size(root)))

	// Remove node with one child
	root = node_remove(root, Key{5, 2})
	testing.expect(t, node_search(root, Key{5, 2}) == nil, "key {5,2} should be removed")
	testing.expect(t, node_size(root) == 3, fmt.tprintf("expected size 3, got %d", node_size(root)))

	// Remove node with two children (root-like)
	root = node_remove(root, Key{10, 1})
	testing.expect(t, node_search(root, Key{10, 1}) == nil, "key {10,1} should be removed")
	testing.expect(t, node_size(root) == 2, fmt.tprintf("expected size 2, got %d", node_size(root)))

	// Remaining nodes still findable
	testing.expect(t, node_search(root, Key{7, 5}) != nil, "key {7,5} should still exist")
	testing.expect(t, node_search(root, Key{20, 3}) != nil, "key {20,3} should still exist")
}

@(test)
test_node_remove_nil :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// Remove from nil tree should return nil
	result := node_remove(nil, Key{1, 1})
	testing.expect(t, result == nil, "removing from nil tree should return nil")
}

@(test)
test_node_search_nil :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	result := node_search(nil, Key{1, 1})
	testing.expect(t, result == nil, "searching nil tree should return nil")
}

@(test)
test_node_duplicate_key_appends :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	// Add same key twice — should append to interval list
	root, _ = add_test_node(root, tree, 10, 1, 15)
	root, _ = add_test_node(root, tree, 10, 1, 20)

	testing.expect(t, node_size(root) == 1, "duplicate key should not create new node")

	n := node_search(root, Key{10, 1})
	testing.expect(t, n != nil, "should find node")
	testing.expect(t, len(n.interval.ins) == 2, fmt.tprintf("expected 2 intervals, got %d", len(n.interval.ins)))
}

@(test)
test_node_avl_sorted_insert_balance :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	// Insert 10 nodes in ascending order — worst case for BST, but AVL should balance
	for i := 0; i < 10; i += 1 {
		root, _ = add_test_node(root, tree, i * 10, i, i * 10 + 5)
	}

	testing.expect(t, node_size(root) == 10, fmt.tprintf("expected size 10, got %d", node_size(root)))

	// AVL height for 10 nodes: at most ceil(1.44 * log2(11)) ≈ 5
	h := node_get_height(root)
	testing.expect(t, h <= 5, fmt.tprintf("height %d exceeds expected max 5 for 10 nodes", h))
}

@(test)
test_node_avl_reverse_insert_balance :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	// Insert in descending order — triggers right-heavy rotations
	for i := 10; i > 0; i -= 1 {
		root, _ = add_test_node(root, tree, i * 10, i, i * 10 + 5)
	}

	testing.expect(t, node_size(root) == 10, fmt.tprintf("expected size 10, got %d", node_size(root)))

	h := node_get_height(root)
	testing.expect(t, h <= 5, fmt.tprintf("height %d exceeds expected max 5 for 10 nodes", h))

	// All nodes still findable
	for i := 10; i > 0; i -= 1 {
		n := node_search(root, Key{i * 10, i})
		testing.expect(t, n != nil, fmt.tprintf("should find node at key {%d, %d}", i * 10, i))
	}
}

@(test)
test_node_find_smallest :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	root, _ = add_test_node(root, tree, 50, 1, 55)
	root, _ = add_test_node(root, tree, 20, 2, 25)
	root, _ = add_test_node(root, tree, 80, 3, 85)
	root, _ = add_test_node(root, tree, 10, 4, 15)
	root, _ = add_test_node(root, tree, 30, 5, 35)

	smallest := node_find_smallest(root)
	testing.expect(t, smallest != nil, "smallest should not be nil")
	testing.expect(t, smallest.key.pos == 10, fmt.tprintf("expected smallest pos=10, got %d", smallest.key.pos))
}

@(test)
test_node_height_and_size :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	// nil node
	testing.expect(t, node_get_height(nil) == 0, "nil node height should be 0")
	testing.expect(t, node_size(nil) == 0, "nil node size should be 0")

	tree := make_test_tree()
	root: ^Node

	// Single node
	root, _ = add_test_node(root, tree, 10, 1, 15)
	testing.expect(t, node_get_height(root) == 1, "single node height should be 1")
	testing.expect(t, node_size(root) == 1, "single node size should be 1")

	// Two nodes
	root, _ = add_test_node(root, tree, 5, 2, 8)
	testing.expect(t, node_get_height(root) == 2, fmt.tprintf("expected height 2, got %d", node_get_height(root)))
	testing.expect(t, node_size(root) == 2, "two nodes size should be 2")
}

@(test)
test_node_max_tracking :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	// Add nodes with different high values
	root, _ = add_test_node(root, tree, 10, 1, 15)
	root, _ = add_test_node(root, tree, 5, 2, 100) // highest
	root, _ = add_test_node(root, tree, 20, 3, 25)

	// Root's max should be at least 100 (the highest interval endpoint)
	testing.expect(t, root.max >= 100, fmt.tprintf("root max should be >= 100, got %d", root.max))
}

@(test)
test_node_remove_overlaps :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	root, _ = add_test_node(root, tree, 0, 1, 10)
	root, _ = add_test_node(root, tree, 20, 2, 30)
	root, _ = add_test_node(root, tree, 40, 3, 50)

	// Remove overlaps with [0, 10] — should remove first node
	root = node_remove_overlaps(root, 0, 10)
	testing.expect(t, node_search(root, Key{0, 1}) == nil, "node at pos=0 should be removed by overlap")

	// Others should survive
	testing.expect(t, node_search(root, Key{20, 2}) != nil, "node at pos=20 should survive")
	testing.expect(t, node_search(root, Key{40, 3}) != nil, "node at pos=40 should survive")
}

@(test)
test_node_allvals :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	root, _ = add_test_node(root, tree, 10, 1, 15)
	root, _ = add_test_node(root, tree, 5, 2, 8)
	root, _ = add_test_node(root, tree, 20, 3, 25)

	acc := make([dynamic]^Entry)
	node_allvals(root, &acc)
	testing.expect(t, len(acc) == 3, fmt.tprintf("expected 3 entries, got %d", len(acc)))
}

@(test)
test_node_shift_updates_positions :: proc(t: ^testing.T) {
	arena: virtual.Arena
	assert(virtual.arena_init_growing(&arena) == .None)
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	tree := make_test_tree()
	root: ^Node

	root, _ = add_test_node(root, tree, 10, 1, 20)
	root, _ = add_test_node(root, tree, 30, 2, 40)

	// Apply a shift: everything at or after idx=5 shifts by +10
	tree.root = root
	tree_shift(tree, 5, 10)

	// After shift, node at original pos=10 should now be at pos=20
	// We need to search for the shifted key
	node_apply_all_shifts(tree.root)
	n := node_search(tree.root, Key{20, 1})
	testing.expect(t, n != nil, "node originally at pos=10 should be at pos=20 after shift +10")

	n2 := node_search(tree.root, Key{40, 2})
	testing.expect(t, n2 != nil, "node originally at pos=30 should be at pos=40 after shift +10")
}
