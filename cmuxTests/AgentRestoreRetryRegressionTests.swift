import CmuxFoundation
import Darwin
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite("Agent restore retry regressions", .serialized)
struct AgentRestoreRetryRegressionTests {
    @Test("Deferred restore revalidates an owner that exits after index load")
    func deferredRestoreRevalidatesExitedOwner() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-deferred-owner-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let workspaceID = UUID()
        let panelID = UUID()
        let sessionID = "deferred-owner-exit"
        let processID = 987_654_321
        let identity = AgentPIDProcessIdentity(
            pid: pid_t(processID),
            startSeconds: 1_800_000_500,
            startMicroseconds: 0
        )
        let key = RestorableAgentSessionIndex.PanelKey(
            workspaceId: workspaceID,
            panelId: panelID
        )
        let snapshot = SessionRestorableAgentSnapshot(
            kind: .codex,
            sessionId: sessionID,
            workingDirectory: "/tmp",
            launchCommand: nil
        )
        let index = RestorableAgentSessionIndex.load(
            homeDirectory: root.path,
            fileManager: fileManager,
            registry: CmuxVaultAgentRegistry(registrations: []),
            detectedSnapshots: [key: (
                snapshot: snapshot,
                updatedAt: 1_800_000_500,
                processIDs: [processID],
                agentProcessIDs: [processID],
                sessionIDSource: .explicit
            )],
            processArgumentsProvider: { _ in nil },
            processPresenceProvider: { _ in .present },
            processIdentityProvider: { _ in identity }
        )

        #expect(index.hasDeferredRestoreProcessConflict(
            workspaceId: workspaceID,
            panelId: panelID,
            processIdentityProvider: { _ in identity },
            processPresenceProvider: { _ in .present }
        ))
        #expect(index.hasDeferredRestoreProcessConflict(
            workspaceId: workspaceID,
            panelId: panelID,
            processIdentityProvider: { _ in nil },
            processPresenceProvider: { _ in .unknown }
        ))
        #expect(!index.hasDeferredRestoreProcessConflict(
            workspaceId: workspaceID,
            panelId: panelID,
            processIdentityProvider: { _ in nil },
            processPresenceProvider: { _ in .absent }
        ))
    }

    @Test("Workspace preserves running intent after retryable restore cancellation")
    func workspacePreservesRetryableRestoreIntent() throws {
        let workspace = Workspace()
        defer { workspace.teardownAllPanels() }
        let panelID = try #require(workspace.focusedPanelId)
        let binding = agentHookBinding(checkpoint: "retryable-workspace-session")
        #expect(workspace.setSurfaceResumeBinding(binding, panelId: panelID))
        workspace.deferredAgentResumeRestoresByPanelId[panelID] = deferredRestore(
            panelID: panelID,
            binding: binding
        )

        workspace.clearDeferredAgentResumeRestores(retireBindings: false)

        let snapshot = workspace.sessionSnapshot(
            includeScrollback: false,
            restorableAgentIndex: .empty
        )
        let terminal = try #require(snapshot.panels.first { $0.id == panelID }?.terminal)
        #expect(terminal.wasAgentRunning == true)
    }

    @Test("Dock preserves running intent after retryable restore cancellation")
    func dockPreservesRetryableRestoreIntent() throws {
        let store = DockSplitStore(
            workspaceId: UUID(),
            baseDirectoryProvider: { "/tmp" }
        )
        defer { store.closeAllPanels() }
        let paneID = try #require(store.bonsplitController.allPaneIds.first)
        let panelID = try #require(
            store.newSurface(kind: .terminal, inPane: paneID, focus: false)
        )
        let binding = agentHookBinding(checkpoint: "retryable-dock-session")
        #expect(store.setSurfaceResumeBinding(binding, panelId: panelID))
        store.restoredAgentLifecycle.setResumeState(.manualResumeAvailable, panelId: panelID)

        let snapshot = store.sessionSnapshot(
            includeScrollback: false,
            restorableAgentIndex: .empty
        )
        let terminal = try #require(snapshot.panels.first { $0.id == panelID }?.terminal)
        #expect(terminal.wasAgentRunning == true)
    }

    private func agentHookBinding(checkpoint: String) -> SurfaceResumeBindingSnapshot {
        SurfaceResumeBindingSnapshot(
            name: "Codex",
            kind: "codex",
            command: "codex resume \(checkpoint)",
            cwd: "/tmp",
            checkpointId: checkpoint,
            source: "agent-hook",
            autoResume: true,
            updatedAt: 1_800_000_500
        )
    }

    private func deferredRestore(
        panelID: UUID,
        binding: SurfaceResumeBindingSnapshot
    ) -> DeferredAgentResumeRestore {
        DeferredAgentResumeRestore(
            stablePanelID: panelID,
            restorableAgent: nil,
            resumeBinding: binding,
            restoresRemoteWorkspaceTerminalSnapshot: false,
            workingDirectory: "/tmp",
            resumeWorkingDirectory: "/tmp"
        )
    }
}
