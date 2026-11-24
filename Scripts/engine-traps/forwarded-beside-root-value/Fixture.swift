import SafeDI

// One reader of `id` built in three places: beneath a builder that forwards an `id`, beneath another type that
// forwards an `id`, and beneath the root, where `id` is a value the mock is passed.

@Instantiable(isRoot: true, generateMock: true)
public final class Root: Instantiable {
	public init(id: ID, reader: Reader, pageBuilder: Instantiator<Page>, sheetBuilder: Instantiator<Sheet>) {
		self.id = id
		self.reader = reader
		self.pageBuilder = pageBuilder
		self.sheetBuilder = sheetBuilder
	}

	@Instantiated let id: ID
	@Instantiated let reader: Reader
	@Instantiated let pageBuilder: Instantiator<Page>
	@Instantiated let sheetBuilder: Instantiator<Sheet>
}

@Instantiable
public final class Page: Instantiable {
	public init(id: ID, reader: Reader) {
		self.id = id
		self.reader = reader
	}

	@Forwarded let id: ID
	@Instantiated let reader: Reader
}

@Instantiable
public final class Sheet: Instantiable {
	public init(id: ID, reader: Reader, pageBuilder: Instantiator<Page>) {
		self.id = id
		self.reader = reader
		self.pageBuilder = pageBuilder
	}

	@Forwarded let id: ID
	@Instantiated let reader: Reader
	@Instantiated let pageBuilder: Instantiator<Page>
}

@Instantiable
public final class Reader: Instantiable {
	public init(id: ID, inner: Inner) {
		self.id = id
		self.inner = inner
	}

	@Received let id: ID
	@Instantiated let inner: Inner
}

@Instantiable
public final class Inner: Instantiable {
	public init(id: ID) {
		self.id = id
	}

	@Received let id: ID
}

@Instantiable
public final class ID: Instantiable {
	public init() {}
}
