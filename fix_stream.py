
with open('lib/screens/devcom_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

old_block = '''                  if (submission.cbvrStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('AI Video Analysis (Smart Search)',
                                style: TextStyle(color: _textSecondary, fontSize: 13)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (submission.cbvrStatus != 'completed' && submission.cbvrStatus != 'failed')
                                  const SizedBox(
                                    width: 10, height: 10,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: _pendingColor),
                                  ),
                                if (submission.cbvrStatus != 'completed' && submission.cbvrStatus != 'failed')
                                  const SizedBox(width: 6),
                                Expanded(
                                  child: (submission.cbvrStatus == 'waiting' || submission.cbvrStatus == 'downloading')
                                    ? _PreparingVideoText(submission: submission)
                                    : Text(
                                      (() {
                                        switch (submission.cbvrStatus) {
                                          case 'completed': return '? AI Insight Ready';
                                          case 'failed': return '? AI Analysis Failed';
                                          case 'analyzing': return '?? AI is watching the video...';
                                          case 'uploading': return '?? Uploading video to AI...';
                                          default: return '? Processing...';
                                        }
                                      })(),
                                      style: TextStyle(
                                        color: submission.cbvrStatus == 'failed'
                                          ? _returnedColor
                                          : submission.cbvrStatus == 'completed'
                                            ? _approvedColor
                                            : _pendingColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                    ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Starting AI analysis...'), backgroundColor: _pendingColor),
                            );
                            Navigator.pop(ctx);
                            await FirebaseFunctions.instance.httpsCallable('retryCBVRMetadata').call({'filmId': submission.id});
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('AI Analysis complete!'), backgroundColor: _approvedColor),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: '), backgroundColor: _returnedColor),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.smart_toy_outlined, size: 16),
                        label: Text(submission.cbvrStatus == 'completed' ? 'Re-analyze' : 'Retry AI'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1A2B1A),
                          foregroundColor: _approvedColor,
                          side: const BorderSide(color: _approvedColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white12),
                ],'''

new_block = '''                  if (submission.cbvrStatus.isNotEmpty)
                    StreamBuilder<DocumentSnapshot>(
                      stream: FirebaseFirestore.instance.collection('films').doc(submission.id).snapshots(),
                      builder: (ctxStream, snapshot) {
                        if (snapshot.hasData && snapshot.data!.data() != null) {
                          final data = snapshot.data!.data() as Map<String, dynamic>;
                          submission.cbvrStatus = data['cbvrStatus'] as String? ?? submission.cbvrStatus;
                          submission.cbvrError = data['cbvrError'] as String? ?? submission.cbvrError;
                        }
                        
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('AI Video Analysis (Smart Search)',
                                          style: TextStyle(color: _textSecondary, fontSize: 13)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (submission.cbvrStatus != 'completed' && submission.cbvrStatus != 'failed')
                                            const SizedBox(
                                              width: 10, height: 10,
                                              child: CircularProgressIndicator(strokeWidth: 1.5, color: _pendingColor),
                                            ),
                                          if (submission.cbvrStatus != 'completed' && submission.cbvrStatus != 'failed')
                                            const SizedBox(width: 6),
                                          Expanded(
                                            child: (submission.cbvrStatus == 'waiting' || submission.cbvrStatus == 'downloading')
                                              ? _PreparingVideoText(submission: submission, key: ValueKey(submission.cbvrStatus))
                                              : Text(
                                                (() {
                                                  switch (submission.cbvrStatus) {
                                                    case 'completed': return '? AI Insight Ready';
                                                    case 'failed': return '? AI Analysis Failed';
                                                    case 'analyzing': return '?? AI is watching the video...';
                                                    case 'uploading': return '?? Uploading video to AI...';
                                                    default: return '? Processing...';
                                                  }
                                                })(),
                                                style: TextStyle(
                                                  color: submission.cbvrStatus == 'failed'
                                                    ? _returnedColor
                                                    : submission.cbvrStatus == 'completed'
                                                      ? _approvedColor
                                                      : _pendingColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600),
                                              ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: (submission.cbvrStatus == 'analyzing' || submission.cbvrStatus == 'uploading' || submission.cbvrStatus == 'waiting' || submission.cbvrStatus == 'downloading') ? null : () async {
                                    try {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Starting AI analysis...'), backgroundColor: _pendingColor),
                                      );
                                      // Remove Navigator.pop(ctx) so it stays open
                                      await FirebaseFunctions.instance.httpsCallable('retryCBVRMetadata').call({'filmId': submission.id});
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('AI Analysis complete!'), backgroundColor: _approvedColor),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed: '), backgroundColor: _returnedColor),
                                        );
                                      }
                                    }
                                  },
                                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                                  label: Text(submission.cbvrStatus == 'completed' ? 'Re-analyze' : 'Retry AI'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1A2B1A),
                                    foregroundColor: _approvedColor,
                                    side: const BorderSide(color: _approvedColor),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Divider(color: Colors.white12),
                          ],
                        );
                      }
                    ),'''

c = c.replace(old_block, new_block)

with open('lib/screens/devcom_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print('Stream builder added')

