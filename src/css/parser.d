module css.parser;


import std.ascii;
import std.traits;


private enum ParserStates {
	Global = 0,
	SkipWhite,
	PreComment,
	Comment,
	PostComment,
	Selector,
	At,
	Block,
	PropertyName,
	PostPropertyName,
	PropertyValue,
	StringDQ,
	StringSQ,
}


private bool isSpace(Char)(Char ch) {
	return (ch == 32) || ((ch >= 9) && (ch <= 13));
}


private auto ref strip(T)(T x) if (isArray!T) {
	auto right = x.length;
	auto left = 0;
	while ((left < right) && isSpace(x[left]))
		++left;
	while ((left < right) && isSpace(x[right-1]))
		--right;
	return x[left..right];
}


enum ParserOptions {
	None = 0,
	Default = 0,
}


void parseCSS(Handler, size_t options = ParserOptions.Default)(const(char)[] source, ref Handler handler) {
	auto ptr = source.ptr;
	auto end = source.ptr + source.length;
	auto start = ptr;

	ParserStates state = ParserStates.SkipWhite;
	ParserStates saved = ParserStates.Global;
	ParserStates targetSkip = ParserStates.Global;

	void skipWhiteFor(ParserStates target) {
		targetSkip = target;
		state = ParserStates.SkipWhite;
	}

	while (ptr != end) {
		final switch (state) with (ParserStates) {
		case Global:
			if ((*ptr == '.') || (*ptr == '#') || isAlpha(*ptr)) {
				start = ptr;
				state = Selector;
			} else if (*ptr == '@') {
				state = At;
				start = ptr;
			}
			break;

		case SkipWhite:
			while ((ptr != end) && isSpace(*ptr) && (*ptr != '/'))
				++ptr;
			if (ptr == end)
				continue;

			if ((*ptr != '/') || ((ptr + 1) == end) || (*(ptr + 1) != '*')) {
				state = targetSkip;
				start = ptr;
				continue;
			} else {
				saved = SkipWhite;
				state = PreComment;
			}
			break;

		case Selector:
			while ((ptr != end) && (*ptr != '{') && (*ptr != ',') && (*ptr != '/') && (*ptr != '\"') && (*ptr != '\''))
				++ptr;
			if (ptr == end)
				continue;

			if ((*ptr != '/') || ((ptr + 1) == end) || (*(ptr + 1) != '*')) {
				if (*ptr == '{') {
					if (start < ptr)
						handler.onSelector(start[0..ptr-start].strip);
					handler.onSelectorEnd();

					skipWhiteFor(Block);
				} else if (*ptr == ',') {
					if (start < ptr)
						handler.onSelector(start[0..ptr-start].strip);
					handler.onSelectorEnd();
					skipWhiteFor(Selector);
				} else if (*ptr == '\"') {
					saved = Selector;
					state = StringDQ;
				} else if (*ptr == '\'') {
					saved = Selector;
					state = StringSQ;
				}
			} else {
				saved = Selector;
				state = PreComment;
			}
			break;

		case At:
			break;

		case Block:
			if (*ptr != '}') {
				start = ptr;
				state = PropertyName;
				continue;
			} else {
				handler.onBlockEnd();
				skipWhiteFor(Global);
			}
			break;

		case PropertyName:
			while ((ptr != end) && (isAlpha(*ptr) || (*ptr == '-') || (*ptr == '_')))
				++ptr;
			if (ptr == end)
				continue;

			handler.onPropertyName(start[0..ptr-start].strip);

			skipWhiteFor(PostPropertyName);
			continue;

		case PostPropertyName:
			while ((ptr != end) && (*ptr != ':'))
				++ptr;
			if (ptr == end)
				continue;

			skipWhiteFor(PropertyValue);
			break;

		case PropertyValue:
			while ((ptr != end) && (*ptr != ';') && (*ptr != '}') && (*ptr != '/') && (*ptr != '\"') && (*ptr != '\''))
				++ptr;
			if (ptr == end)
				continue;

			if ((*ptr != '/') || ((ptr + 1) == end) || (*(ptr + 1) != '*')) {
				if (*ptr == ';') {
					if (start < ptr)
						handler.onPropertyValue(start[0..ptr-start].strip);
					handler.onPropertyValueEnd();
					skipWhiteFor(Block);
				} else if (*ptr == '}') {
					if (start < ptr)
						handler.onPropertyValue(start[0..ptr-start].strip);
					handler.onPropertyValueEnd();
					skipWhiteFor(Global);
				} else if (*ptr == '\"') {
					saved = PropertyValue;
					state = StringDQ;
				} else if (*ptr == '\'') {
					saved = PropertyValue;
					state = StringSQ;
				}
			} else {
				if (start < ptr)
					handler.onPropertyValue(start[0..ptr-start].strip);

				saved = PropertyValue;
				state = PreComment;
			}
			break;

		case PreComment:
			if (*ptr == '*') {
				state = Comment;
				start = ptr + 1;
			} else {
				state = saved;
			}
			break;

		case Comment:
			while ((ptr != end) && (*ptr != '*'))
				++ptr;
			if (ptr == end)
				continue;

			state = PostComment;
			break;

		case PostComment:
			if (*ptr == '/') {
				handler.onComment(start[0..ptr-start-1]);

				state = saved;
				start = ptr + 1;
			} else {
				state = Comment;
			}
			break;

		case StringDQ:
			while ((ptr != end) && (*ptr != '\"'))
				++ptr;
			if (ptr == end)
				continue;

			state = saved;
			break;

		case StringSQ:
			while ((ptr != end) && (*ptr != '\''))
				++ptr;
			if (ptr == end)
				continue;

			state = saved;
			break;
		}

		++ptr;
	}

	if (start < ptr) {
		switch (state) with (ParserStates) {
		case StringDQ:
			if (saved == PropertyValue) {
				handler.onPropertyValue(start[0..ptr-start]);
				handler.onPropertyValue("\"");
				handler.onPropertyValueEnd();
			}
			break;
		case StringSQ:
			if (saved == PropertyValue) {
				handler.onPropertyValue(start[0..ptr-start]);
				handler.onPropertyValue("\'");
				handler.onPropertyValueEnd();
			}
			break;
		case PropertyValue:
			handler.onPropertyValue(start[0..ptr-start].strip);
			handler.onPropertyValueEnd();
			break;
		case Comment:
			handler.onComment(start[0..ptr-start]);
			break;
		case PostComment:
			handler.onComment(start[0..ptr-start-1]);
			break;
		default:
			break;
		}
	}
}


unittest {
	void print(Args...)(string x, Args args) {
		import std.stdio;

		stdout.write(x);
		static if (args.length) {
			stdout.write(": ");
		}
		foreach(arg; args) {
			stdout.write('[');
			stdout.write(arg);
			stdout.write(']');
		}
		writeln();
	}

	struct CSSHandler {
		void onSelector(const(char)[] data) {
			print("selector", data);
		}

		void onSelectorEnd() {
			print("selector end");
		}

		void onBlockEnd() {
			print("block end");
		}

		void onPropertyName(const(char)[] data) {
			print("property", data);
		}

		void onPropertyValue(const(char)[] data) {
			print("value", data);
		}

		void onPropertyValueEnd() {
			print("value end");
		}

		void onComment(const(char)[] data) {
			print("comment", data);
		}
	}


	auto handler = CSSHandler();
	parseCSS(`/* asd asd asdas das dasd */
			 h1 {
			 display : none;
			 /* meh meh meh */
			 border : 1px solid black !important; /* meh meh meh */
			 }`, handler);

	parseCSS(`h1 /* bleh */ {
			 /*before name*/display/*after name*/:/*before value*/none/*after value*/;
			 }`, handler);

	parseCSS(`h1{}`, handler);
	parseCSS(`h1[type=input] {}`, handler);
	parseCSS(`h1, h2, h3.meh, h4 .meh, /* bleh */ {
			 display : /*before value */ none /* after value*/;
			 }`, handler);
	parseCSS(`h[example="dasdas{{dasd"], p:before { content: 'Hello`, handler);
}
