import CmuxFoundation
import Darwin
import Foundation

/// Process-backed index loading shares census ownership and preserves cancellation.
extension RestorableAgentSessionIndex {
    #if compiler(>=6.2)
    @concurrent
    #else
    @Sendable
    #endif
    static func loadIncludingProcessDetectedSnapshots(
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) async -> RestorableAgentSessionIndex {
        let snapshot = await CmuxTopProcessSnapshot.capture(includeProcessDetails: true, includeResources: false)
        return loadIncludingProcessDetectedSnapshotsSynchronously(
            processSnapshot: snapshot, homeDirectory: homeDirectory,
            fileManager: fileManager
        )
    }
    static func loadIncludingProcessDetectedSnapshotsSynchronously(
        processSnapshot: CmuxTopProcessSnapshot,
        homeDirectory: String = NSHomeDirectory(),
        fileManager: FileManager = .default
    ) -> RestorableAgentSessionIndex {
        guard processSnapshot.captureIsAvailable, processSnapshot.enumerationIsComplete, !Task.isCancelled else { return .unavailable }
        let registry = CmuxVaultAgentRegistry.load(homeDirectory: homeDirectory, fileManager: fileManager)
        let detectedSnapshots = processDetectedSnapshots(
            registry: registry,
            fileManager: fileManager,
            processSnapshot: processSnapshot,
            capturedAt: processSnapshot.sampledAt.timeIntervalSince1970
        )
        let hibernationProcessScopes = detectedSnapshots.mapValues { detected in
            processSnapshot.agentHibernationProcessScope(
                panelProcessIDs: detected.processIDs,
                agentProcessIDs: detected.agentProcessIDs
            )
        }
        return load(
            homeDirectory: homeDirectory,
            fileManager: fileManager,
            registry: registry,
            detectedSnapshots: detectedSnapshots,
            hibernationProcessScopes: hibernationProcessScopes
        )
    }

    /// Revalidates retained owners before deferred restore admission. Cached
    /// PID evidence may be stale by the time the shared index finishes loading.
    func hasDeferredRestoreProcessConflict(
        workspaceId: UUID,
        panelId: UUID,
        processIdentityProvider: (Int) -> AgentPIDProcessIdentity? = {
            guard $0 > 0, $0 <= Int(Int32.max) else { return nil }
            return AgentPIDProcessIdentity(pid: pid_t($0))
        },
        processPresenceProvider: (Int) -> PIDPresence = {
            guard $0 > 0, $0 <= Int(Int32.max) else { return .absent }
            return PIDPresence.current(pid: pid_t($0))
        }
    ) -> Bool {
        hasCurrentAmbiguousPanel(
            panelId,
            processIdentityProvider: processIdentityProvider,
            processPresenceProvider: processPresenceProvider
        ) || hasCurrentLiveProcessForStablePanel(
            workspaceId: workspaceId,
            panelId: panelId,
            processIdentityProvider: processIdentityProvider,
            processPresenceProvider: processPresenceProvider
        )
    }
}
