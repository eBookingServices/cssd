# cssd
CSS library for D

The library currently includes a non-validating parser module and a DOM agnostic (currently through an element proxy template) selector matching module
The selector matching module currently implements all CSS3 and the case-insensitive attribute matching from CSS4. Pseudo-elements are currently left to be handled by the user code to minimize the proxy template interface.

Example handler:
```d
struct CSSOMBuilder {
	void onSelector(const(char)[] data) {}
	void onSelectorEnd() {}
	void onBlockEnd() {}
	void onPropertyName(const(char)[] data) {}
	void onPropertyValue(const(char)[] data) {}
	void onPropertyValueEnd() {}
	void onComment(const(char)[] data) {}
}
```

Example usage:
```d
auto builder = CSSOMBuilder();
parseHTML(`h1:hover > span#highlight { background: black; }`, builder);
```

Example selector usage:
```d
	auto highlightSelector = Selector.parse("h1:hover > span#highlight"); // parses selector into a representation that is fast to test
	if (highlightSelector.matches(someElement))
		someElement.attr("style", highlightStyle);
```