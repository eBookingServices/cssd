module css.selector;


import std.algorithm;
import std.array;
import std.ascii;
import std.string;


private bool isSpace(Char)(Char ch) {
	return (ch == 32) || ((ch >= 9) && (ch <= 13));
}


private bool equalsCI(CharA, CharB)(const(CharA)[] a, const(CharB)[] b) {
	if (a.length == b.length) {
		for (uint i = 0; i < a.length; ++i) {
			if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[i]))
				return false;
		}
		return true;
	}
	return false;
}


private struct Rule {
	enum Flags : size_t {
		HasTag          = 1 << 0,
		HasAttr         = 1 << 1,
		HasPseudo       = 1 << 2,
		CaseSensitive   = 1 << 3,
		HasAny          = 1 << 4,
	}

	enum MatchType : ubyte {
		None = 0,
		Set,
		Exact,
		ContainWord,
		Contain,
		Begin,
		BeginHyphen,
		End,
	}

	enum Relation : ubyte {
		None = 0,
		Descendant,
		Child,
		DirectAdjacent,
		IndirectAdjacent,
	}

	bool matches(ElementType)(ElementType element) const {
		if (flags_ == 0)
			return false;

		if (flags_ & Flags.HasTag) {
			if (!tag_.equalsCI(element.tag))
				return false;
		}

		if (flags_ & Flags.HasAttr) {
			auto cs = (flags_ & Flags.CaseSensitive) != 0;
			final switch (match_) with (MatchType) {
			case None:
				break;
			case Set:
				if (element.attr(attr_) == null)
					return false;
				break;
			case Exact:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr || (cs ? (value_ != *pattr) : !value_.equalsCI(*pattr)))
					return false;
				break;
			case Contain:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr || (((*pattr).indexOf(value_, cs ? CaseSensitive.yes : CaseSensitive.no)) == -1))
					return false;
				break;
			case ContainWord:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr)
					return false;

				size_t start = 0;
				while (true) {
					auto index = (*pattr).indexOf(value_, start, cs ? CaseSensitive.yes : CaseSensitive.no);
					if (index == -1)
						return false;
					if (index && !isSpace((*pattr)[index - 1]))
						return false;
					if ((index + value_.length == pattr.length) || isSpace((*pattr)[index + value_.length]))
						break;
					start = index + 1;
				}
				break;
			case Begin:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr || (((*pattr).indexOf(value_, cs ? CaseSensitive.yes : CaseSensitive.no)) != 0))
					return false;
				break;
			case End:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr || (((*pattr).lastIndexOf(value_, cs ? CaseSensitive.yes : CaseSensitive.no)) != (pattr.length - value_.length)))
					return false;
				break;
			case BeginHyphen:
				if (value_.empty) return false;
				auto pattr = element.attr(attr_);
				if (!pattr || (((*pattr).indexOf(value_, cs ? CaseSensitive.yes : CaseSensitive.no)) != 0) || ((pattr.length > value_.length) && ((*pattr)[value_.length] != '-')))
					return false;
				break;
		   }
		}

		if (flags_ & Flags.HasPseudo) {
			if (!element.pseudo(pseudo_, pseudoArg_))
				return false;
		}

		return true;
	}

	@property Relation relation() {
		return relation_;
	}

package:
	size_t flags_;
	MatchType match_;
	Relation relation_;
	const(char)[] tag_;
	const(char)[] attr_;
	const(char)[] value_;
	const(char)[] pseudo_;
	const(char)[] pseudoArg_;
}


struct Selector {
	static Selector parse(const(char)[] value) {
		enum ParserStates {
			Identifier = 0,
			PostIdentifier,
			Tag,
			Class,
			ID,
			AttrName,
			AttrOp,
			PreAttrValue,
			AttrValueDQ,
			AttrValueSQ,
			AttrValueNQ,
			PostAttrValue,
			Pseudo,
			PseudoArgs,
			Relation,
		}

		value = value.strip;
		auto source = uninitializedArray!(char[])(value.length + 1);
		source[0..value.length] = value;
		source[$-1] = ' '; // add a padding space to ease parsing

		auto selector = Selector(source);
		Rule[] rules;
		rules.reserve(2);
		++rules.length;

		auto rule = &rules.back;

		auto ptr = source.ptr;
		auto end = source.ptr + source.length;
		auto start = ptr;

		ParserStates state = ParserStates.Identifier;

		while (ptr != end) {
			final switch (state) with (ParserStates) {
			case Identifier:
				if (*ptr == '#') {
					state = ID;
					start = ptr + 1;
				} else if (*ptr == '.') {
					state = Class;
					start = ptr + 1;
				} else if (*ptr == '[') {
					state = AttrName;
					start = ptr + 1;
				} else if (isAlpha(*ptr)) {
					state = Tag;
					start = ptr;
					continue;
				} else if (*ptr == '*') {
					rule.flags_ |= Rule.Flags.HasAny;
					state = PostIdentifier;
				}
				break;

			case PostIdentifier:
				switch (*ptr) {
				case '#':
					state = ID;
					start = ptr + 1;
					break;
				case '.':
					state = Class;
					start = ptr + 1;
					break;
				case '[':
					state = AttrName;
					start = ptr + 1;
					break;
				case ':':
					state = Pseudo;
					if ((ptr + 1 != end) && (*(ptr + 1) == ':'))
						++ptr;
					start = ptr + 1;
					break;
				default:
					state = Relation;
					continue;
				}
				break;

			case Tag:
				while ((ptr != end) && isAlpha(*ptr))
					++ptr;
				if (ptr == end)
					continue;

				rule.flags_ |= Rule.Flags.HasTag;
				rule.tag_ = start[0..ptr-start];

				state = PostIdentifier;
				continue;

			case Class:
				while ((ptr != end) && (isAlphaNum(*ptr) || (*ptr == '-') || (*ptr == '_')))
					++ptr;
				if (ptr == end)
					continue;

				rule.flags_ |= Rule.Flags.HasAttr;
				rule.match_ = Rule.MatchType.ContainWord;
				rule.attr_ = "class";
				rule.value_ = start[0..ptr-start];

				state = PostIdentifier;
				break;

			case ID:
				while ((ptr != end) && (isAlphaNum(*ptr) || (*ptr == '-') || (*ptr == '_')))
					++ptr;
				if (ptr == end)
					continue;

				rule.flags_ |= Rule.Flags.HasAttr;
				rule.match_ = Rule.MatchType.Exact;
				rule.attr_ = "id";
				rule.value_ = start[0..ptr-start];

				state = PostIdentifier;
				break;

			case AttrName:
				while ((ptr != end) && (isAlphaNum(*ptr) || (*ptr == '-') || (*ptr == '_')))
					++ptr;
				if (ptr == end)
					continue;

				rule.flags_ |= Rule.Flags.HasAttr;
				rule.flags_ |= Rule.Flags.CaseSensitive;
				rule.attr_ = start[0..ptr-start];
				state = AttrOp;
				continue;

			case AttrOp:
				while ((ptr != end) && (isSpace(*ptr)))
					++ptr;
				if (ptr == end)
					continue;

				switch (*ptr) {
				case ']':
					rule.match_ = Rule.MatchType.Set;
					state = PostIdentifier;
					break;
				case '=':
					rule.match_ = Rule.MatchType.Exact;
					state = PreAttrValue;
					break;
				default:
					if ((ptr + 1 != end) && (*(ptr + 1) == '=')) {
						switch (*ptr) {
						case '~':
							rule.match_ = Rule.MatchType.ContainWord;
							break;
						case '^':
							rule.match_ = Rule.MatchType.Begin;
							break;
						case '$':
							rule.match_ = Rule.MatchType.End;
							break;
						case '*':
							rule.match_ = Rule.MatchType.Contain;
							break;
						case '|':
							rule.match_ = Rule.MatchType.BeginHyphen;
							break;
						default:
							rule.flags_ = 0; // error
							ptr = end - 1;
							break;
						}

						state = PreAttrValue;
						++ptr;
					}
					break;
				}
				break;

			case PreAttrValue:
				while ((ptr != end) && isSpace(*ptr))
					++ptr;
				if (ptr == end)
					continue;

				if (*ptr == '\"') {
					state = AttrValueDQ;
					start = ptr + 1;
				} else if (*ptr == '\'') {
					state = AttrValueSQ;
					start = ptr + 1;
				} else {
					state = AttrValueNQ;
					start = ptr;
				}
				break;

			case AttrValueDQ:
				while ((ptr != end) && (*ptr != '\"'))
					++ptr;
				if (ptr == end)
					continue;

				rule.value_ = start[0..ptr-start];
				state = PostAttrValue;
				break;

			case AttrValueSQ:
				while ((ptr != end) && (*ptr != '\''))
					++ptr;
				if (ptr == end)
					continue;

				rule.value_ = start[0..ptr-start];
				state = PostAttrValue;
				break;

			case AttrValueNQ:
				while ((ptr != end) && !isSpace(*ptr) && (*ptr != ']'))
					++ptr;
				if (ptr == end)
					continue;

				rule.value_ = start[0..ptr-start];
				state = PostAttrValue;
				continue;

			case PostAttrValue:
				while ((ptr != end) && (*ptr != ']') && (*ptr != 'i'))
					++ptr;
				if (ptr == end)
					continue;

				if (*ptr == ']') {
					state = PostIdentifier;
				} else if (*ptr == 'i') {
					rule.flags_ &= ~(Rule.Flags.CaseSensitive);
				}
				break;

			case Pseudo:
				while ((ptr != end) && (isAlpha(*ptr) || (*ptr == '-')))
					++ptr;
				if (ptr == end)
					continue;

				rule.pseudo_ = start[0..ptr-start];
				rule.flags_ |= Rule.Flags.HasPseudo;
				if (*ptr != '(') {
					state = PostIdentifier;
					continue;
				} else {
					state = PseudoArgs;
					start = ptr + 1;
				}
				break;

			case PseudoArgs:
				while ((ptr != end) && (*ptr != ')'))
					++ptr;
				if (ptr == end)
					continue;

				rule.pseudoArg_ = start[0..ptr-start];
				state = PostIdentifier;
				break;

			case Relation:
				while ((ptr != end) && isSpace(*ptr))
					++ptr;
				if (ptr == end)
					continue;

				++rules.length;
				rule = &rules.back;

				state = Identifier;
				switch (*ptr) {
				case '>':
					rule.relation_ = Rule.Relation.Child;
					break;
				case '+':
					rule.relation_ = Rule.Relation.DirectAdjacent;
					break;
				case '~':
					rule.relation_ = Rule.Relation.IndirectAdjacent;
					break;
				default:
					rule.relation_ = Rule.Relation.Descendant;
					continue;
				}
				break;
			}

			++ptr;
		}

		rules.reverse();
		selector.rules_ = rules;

		return selector;
	}

	bool matches(ElementType)(ElementType element) {
		if (rules_.empty)
			return false;

		Rule.Relation relation = Rule.Relation.None;
		foreach(ref rule; rules_) {
			final switch (relation) with (Rule.Relation) {
			case None:
				if (!rule.matches(element))
					return false;
				break;
			case Descendant:
				auto ancestors = element.ancestors();
				while (true) {
					if (ancestors.empty())
						return false;
					auto ancestor = ancestors.front;
					if (rule.matches(ancestor)) {
						element = ancestor;
						break;
					}
					ancestors.popFront;
				}
				break;
			case Child:
				auto ancestors = element.ancestors;
				if (ancestors.empty)
					return false;
				auto ancestor = ancestors.front;
				if (!rule.matches(ancestor))
					return false;
				element = ancestor;
				break;
			case DirectAdjacent:
				auto adjacents = element.adjacents;
				if (adjacents.empty)
					return false;
				auto adjacent = adjacents.front;
				if (!rule.matches(adjacent))
					return false;
				element = adjacent;
				break;
			case IndirectAdjacent:
				auto adjacents = element.adjacents;
				while (true) {
					if (adjacents.empty)
						return false;
					auto adjacent = adjacents.front;
					if (rule.matches(adjacent)) {
						element = adjacent;
						break;
					}
					adjacents.popFront;
				}
				break;
			}

			relation = rule.relation;
		}

		return true;
	}

private:
	const(char)[] source_;
	Rule[] rules_;
}


private struct ElementRange {
	@property bool empty() const {
		return index_ >= elements_.length;
	}

	@property Element front() {
		return elements_[index_];
	}

	@property void popFront() {
		++index_;
	}

	private Element[] elements_;
	private size_t index_;
}

private struct Element {
	const(char)[] tag() const {
		return tag_;
	}

	const(char[])* attr(const(char)[] name) const {
		return name in attrs_;
	}

	bool pseudo(const(char)[] name, const(char)[] arg) const {
		return (name == "active");
	}

	auto adjacents() {
		return ElementRange(adjacents_);
	}

	auto ancestors() {
		return ElementRange(ancestors_);
	}

	const(char)[] tag_;
	const(char)[][const(char)[]] attrs_;
	Element[] ancestors_;
	Element[] adjacents_;
}


unittest {
	bool testSelector(const(char)[] selector, Element e) {
		return Selector.parse(selector).matches(e);
	}

	//writeln(`<div id="odiv" class="container"><div id="idiv"><p id="bar"><span id="foo" class="meh moo"></span><span id="error" class="alert">/span></p></div></div>`);

	auto span = Element("span");
	span.attrs_["id"] = "foo";
	span.attrs_["class"] = "meh moo bleh";

	auto error = Element("span");
	error.attrs_["id"] = "error";
	error.attrs_["class"] = "alert";

	auto aerror = Element("span");
	aerror.attrs_["id"] = "aerror";
	aerror.attrs_["class"] = "alert";

	auto p = Element("p");
	p.attrs_["id"] = "bar";

	auto idiv = Element("div");
	idiv.attrs_["id"] = "idiv";

	auto odiv = Element("div");
	odiv.attrs_["id"] = "odiv";
	odiv.attrs_["class"] = "container";

	span.ancestors_ ~= [ p, idiv, odiv ]; // ancestors in closest-first order
	error.ancestors_ ~= [ p, idiv, odiv ];
	error.adjacents_ ~= span; // previous sibblings in closest-first order

	aerror.ancestors_ ~= [ p, idiv, odiv ];
	aerror.adjacents_ ~= [ error, span ]; // previous sibblings in closest-first order

	p.ancestors_ ~= [ idiv, odiv ];
	idiv.ancestors_ ~= [ odiv ];

	assert(testSelector("#bar", p));
	assert(!testSelector("#bar", span));
	assert(testSelector(".meh", span));
	assert(testSelector(".moo", span));
	assert(testSelector(".bleh", span));
	assert(testSelector("span.bleh", span));
	assert(testSelector(".alert", error));
	assert(testSelector("span.alert", error));
	assert(!testSelector("div.alert", error));
	assert(testSelector("div p", p));
	assert(testSelector("div > p", p));
	assert(testSelector("div span", span));
	assert(testSelector("div span", error));
	assert(!testSelector("div span + span", span));
	assert(!testSelector("div span#foo + span", aerror));
	assert(testSelector("div span#foo ~ span", aerror));
	assert(testSelector("div span.bleh ~ span", error));
	assert(!testSelector("div span#error", span));
	assert(testSelector("div span#error", error));
	assert(testSelector(`div[id="idiv"]`, idiv));
	assert(testSelector(`div[id='idiv']`, idiv));
	assert(testSelector(`div[id=idiv]`, idiv));
	assert(!testSelector(`div[id=IDIV]`, idiv));
	assert(!testSelector(`div[id=IDIV] i`, idiv));
	assert(testSelector(`div[id ^= idiv ]`, idiv));
	assert(testSelector(`div[id ~= idiv i]`, idiv));
	assert(testSelector(`div[id *= div]`, idiv));
	assert(testSelector(`div[id |= IDIV i]:active`, idiv));
	assert(!testSelector(`div[id |= IDIV i]:focus`, idiv));
}
