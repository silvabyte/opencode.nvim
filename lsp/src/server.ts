#!/usr/bin/env node

import {
	type CompletionItem,
	CompletionItemKind,
	createConnection,
	type InitializeParams,
	type InitializeResult,
	ProposedFeatures,
	TextDocumentSyncKind,
	TextDocuments,
} from "vscode-languageserver/node";

import { TextDocument } from "vscode-languageserver-textdocument";

// Create LSP connection
const connection = createConnection(ProposedFeatures.all);

// Text document manager
const documents = new TextDocuments(TextDocument);

// OpenCode client (to be initialized)
const opencodeClient: any = null;

connection.onInitialize((params: InitializeParams): InitializeResult => {
	connection.console.log("[OpenCode LSP] Initializing...");

	return {
		capabilities: {
			textDocumentSync: TextDocumentSyncKind.Incremental,
			completionProvider: {
				resolveProvider: false,
				triggerCharacters: [".", ":", ">", " "],
			},
			hoverProvider: false, // TODO: Implement
			definitionProvider: false, // TODO: Implement
		},
	};
});

connection.onInitialized(() => {
	connection.console.log("[OpenCode LSP] Server initialized");

	// TODO: Initialize OpenCode client
	// This will be implemented in Phase 4
});

// Completion handler
connection.onCompletion(async (params) => {
	connection.console.log("[OpenCode LSP] Completion requested");

	// TODO: Implement actual completion logic
	// For now, return empty array

	const document = documents.get(params.textDocument.uri);
	if (!document) {
		return [];
	}

	// Extract context
	const position = params.position;
	const text = document.getText();
	const offset = document.offsetAt(position);

	// Build context (simplified)
	const beforeText = text.substring(Math.max(0, offset - 1000), offset);
	const afterText = text.substring(offset, Math.min(text.length, offset + 500));

	connection.console.log(
		`[OpenCode LSP] Context: before=${beforeText.length} chars, after=${afterText.length} chars`,
	);

	// TODO: Send to OpenCode server and get completions
	// For now, return placeholder
	const items: CompletionItem[] = [];

	return items;
});

// Make the text document manager listen on the connection
documents.listen(connection);

// Start listening
connection.listen();

connection.console.log("[OpenCode LSP] Server started and listening");
