.PHONY: database

# Database codegen
database:
	@(dart pub get && dart run build_runner build --delete-conflicting-outputs)