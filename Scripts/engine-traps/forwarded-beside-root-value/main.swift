func report(_ name: String, _ value: some Any) { print("\(name): \(value)") }

let root = Root.mock()
let pageID = ID()
let sheetID = ID()
let nestedPageID = ID()
let page = root.pageBuilder.instantiate(pageID)
let sheet = root.sheetBuilder.instantiate(sheetID)
let nestedPage = sheet.pageBuilder.instantiate(nestedPageID)
report("the root's reader reads the root's id", root.reader.id === root.id && root.reader.inner.id === root.id)
report("the page's reader reads the id the page was forwarded", page.reader.id === pageID && page.reader.inner.id === pageID)
report("the sheet's reader reads the id the sheet was forwarded", sheet.reader.id === sheetID && sheet.reader.inner.id === sheetID)
report("the sheet's page's reader reads the id that page was forwarded", nestedPage.reader.id === nestedPageID && nestedPage.reader.inner.id === nestedPageID)

let marked = Root.mock(safeDIOverrides: .init(
	sheetBuilder: .init(pageBuilder: .init(reader: .init(inner: { id in
		print("the sheet's page's inner override was handed the id that page was forwarded: \(id === nestedPageID)")
		return Inner(id: id)
	}))),
))
_ = marked.reader
_ = marked.pageBuilder.instantiate(pageID)
let markedSheet = marked.sheetBuilder.instantiate(sheetID)
print("only the sheet's page calls the override, once:")
_ = markedSheet.pageBuilder.instantiate(nestedPageID)

let production = Root()
let productionSheet = production.sheetBuilder.instantiate(sheetID)
let productionNestedPage = productionSheet.pageBuilder.instantiate(nestedPageID)
report("production: the root's reader reads the root's id", production.reader.id === production.id && production.reader.inner.id === production.id)
report("production: the sheet's reader reads the id the sheet was forwarded", productionSheet.reader.id === sheetID && productionSheet.reader.inner.id === sheetID)
report("production: the sheet's page's reader reads the id that page was forwarded", productionNestedPage.reader.id === nestedPageID && productionNestedPage.reader.inner.id === nestedPageID)
