from collections import MutableMapping, KeysView, ValuesView, ItemsView

from operator import itemgetter as _itemgetter, eq as _eq
from keyword import iskeyword as _iskeyword
import sys as _sys
import heapq as _heapq
from itertools import repeat as _repeat, chain as _chain, starmap as _starmap
from itertools import imap as _imap

try:
    from thread import get_ident as _get_ident
except ImportError:
    from dummy_thread import get_ident as _get_ident


cdef dict_delitem = dict.__delitem__
cdef dict_setitem = dict.__setitem__
cdef _repr_running = {}


cdef class OrderedDict(dict):
    'Dictionary that remembers insertion order'
    # An inherited dict maps keys to values.
    # The inherited dict provides __getitem__, __len__, __contains__, and get.
    # The remaining methods are order-aware.
    # Big-O running times for all methods are the same as regular dictionaries.

    # The internal self.__map dict maps keys to links in a doubly linked list.
    # The circular doubly linked list starts and ends with a sentinel element.
    # The sentinel element never gets deleted (this simplifies the algorithm).
    # Each link is stored as a list of length three:  [PREV, NEXT, KEY].

    cdef dict __map, __fake_dict__
    cdef list __root

    property __dict__:
        def __get__(self):
            if not self.__fake_dict__:
                self.__fake_dict__ =  {'_OrderedDict__root': self.__root,
                                       '_OrderedDict__map': self.__map}
            return self.__fake_dict__

        def __set__(self, value):
            self.__fake_dict__ = value

    def __init__(self, *args, **kwds):
        '''Initialize an ordered dictionary.  The signature is the same as
        regular dictionaries, but keyword arguments are not recommended because
        their insertion order is arbitrary.
        '''
        if len(args) > 1:
            raise TypeError('expected at most 1 arguments, got %d' % len(args))
        if self.__root is None:
            self.__root = root = []                     # sentinel node
            root[:] = [root, root, None]
            self.__map = {}
        self.__update(*args, **kwds)

    def __setitem__(self, key, value):
        'od.__setitem__(i, y) <==> od[i]=y'
        # Setting a new item creates a new link at the end of the linked list,
        # and the inherited dictionary is updated with the new key/value pair.
        if key not in self:
            root = self.__root
            last = root[0]
            last[1] = root[0] = self.__map[key] = [last, root, key]
        dict_setitem(self, key, value)

    def __delitem__(self, key):
        'od.__delitem__(y) <==> del od[y]'
        # Deleting an existing item uses self.__map to find the link which gets
        # removed by updating the links in the predecessor and successor nodes.
        dict_delitem(self, key)
        link_prev, link_next, _ = self.__map.pop(key)
        link_prev[1] = link_next                        # update link_prev[NEXT]
        link_next[0] = link_prev                        # update link_next[PREV]

    def __iter__(self):
        'od.__iter__() <==> iter(od)'
        # Traverse the linked list in order.
        root = self.__root
        curr = root[1]                                  # start at the first node
        while curr is not root:
            yield curr[2]                               # yield the curr[KEY]
            curr = curr[1]                              # move to next node

    def __reversed__(self):
        'od.__reversed__() <==> reversed(od)'
        # Traverse the linked list in reverse order.
        root = self.__root
        curr = root[0]                                  # start at the last node
        while curr is not root:
            yield curr[2]                               # yield the curr[KEY]
            curr = curr[0]                              # move to previous node

    def clear(self):
        'od.clear() -> None.  Remove all items from od.'
        root = self.__root
        root[:] = [root, root, None]
        self.__map.clear()
        dict.clear(self)

    # -- the following methods do not depend on the internal structure --

    def keys(self):
        'od.keys() -> list of keys in od'
        return list(self)

    def values(self):
        'od.values() -> list of values in od'
        return [self[key] for key in self]

    def items(self):
        'od.items() -> list of (key, value) pairs in od'
        return [(key, self[key]) for key in self]

    def iterkeys(self):
        'od.iterkeys() -> an iterator over the keys in od'
        return iter(self)

    def itervalues(self):
        'od.itervalues -> an iterator over the values in od'
        for k in self:
            yield self[k]

    def iteritems(self):
        'od.iteritems -> an iterator over the (key, value) pairs in od'
        for k in self:
            yield (k, self[k])

    update = MutableMapping.update

    __update = update # let subclasses override update without breaking __init__

    __marker = object()

    def pop(self, key, default=__marker):
        '''od.pop(k[,d]) -> v, remove specified key and return the corresponding
        value.  If key is not found, d is returned if given, otherwise KeyError
        is raised.
        '''
        if key in self:
            result = self[key]
            del self[key]
            return result
        if default is self.__marker:
            raise KeyError(key)
        return default

    def setdefault(self, key, default=None):
        'od.setdefault(k[,d]) -> od.get(k,d), also set od[k]=d if k not in od'
        if key in self:
            return self[key]
        self[key] = default
        return default

    def popitem(self, last=True):
        '''od.popitem() -> (k, v), return and remove a (key, value) pair.
        Pairs are returned in LIFO order if last is true or FIFO order if false.
        '''
        if not self:
            raise KeyError('dictionary is empty')
        key = next(reversed(self) if last else iter(self))
        value = self.pop(key)
        return key, value

    def __repr__(self):
        'od.__repr__() <==> repr(od)'
        call_key = id(self), _get_ident()
        if call_key in _repr_running:
            return '...'
        _repr_running[call_key] = 1
        try:
            if not self:
                return '%s()' % (self.__class__.__name__,)
            return '%s(%r)' % (self.__class__.__name__, self.items())
        finally:
            del _repr_running[call_key]

    def __reduce__(self):
        'Return state information for pickling'
        items = [[k, self[k]] for k in self]
        inst_dict = vars(self).copy()
        for k in vars(OrderedDict()):
            inst_dict.pop(k, None)
        if inst_dict:
            return (self.__class__, (items,), inst_dict)
        return self.__class__, (items,)

    def copy(self):
        'od.copy() -> a shallow copy of od'
        return self.__class__(self)

    @classmethod
    def fromkeys(cls, iterable, value=None):
        '''OD.fromkeys(S[, v]) -> New ordered dictionary with keys from S.
        If not specified, the value defaults to None.
        '''
        self = cls()
        for key in iterable:
            self[key] = value
        return self

    def _eq__(self, other):
        '''od.__eq__(y) <==> od==y.  Comparison to another OD is order-sensitive
        while comparison to a regular mapping is order-insensitive.
        '''
        if isinstance(other, OrderedDict):
            return dict.__eq__(self, other) and all(_imap(_eq, self, other))
        return dict.__eq__(self, other)

    def _ne__(self, other):
        'od.__ne__(y) <==> od!=y'
        return not self == other

    def __richcmp__(self, other, int op):
        if op == 2:
            return self._eq__(other)
        if op == 3:
            return self._ne__(other)
        if op == 0:
            return dict.__lt__(self, other)
        if op == 4:
            return dict.__gt__(self, other)
        if op == 1:
            return dict.__le__(self, other)
        if op == 5:
            return dict.__ge__(self, other)

    # -- the following methods support python 3.x style dictionary views --

    def viewkeys(self):
        "od.viewkeys() -> a set-like object providing a view on od's keys"
        return KeysView(self)

    def viewvalues(self):
        "od.viewvalues() -> an object providing a view on od's values"
        return ValuesView(self)

    def viewitems(self):
        "od.viewitems() -> a set-like object providing a view on od's items"
        return ItemsView(self)