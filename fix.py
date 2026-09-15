
with open('lib/screens/devcom_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    c = f.read()

c = c.replace(
    '''                                (submission.cbvrStatus == 'waiting' || submission.cbvrStatus == 'downloading')
                                  ? _PreparingVideoText(submission: submission)
                                  : Text(''',
    '''                                Expanded(
                                  child: (submission.cbvrStatus == 'waiting' || submission.cbvrStatus == 'downloading')
                                    ? _PreparingVideoText(submission: submission)
                                    : Text('''
)

c = c.replace(
    '''                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  ),
                              ],
                            ),''',
    '''                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),'''
)

with open('lib/screens/devcom_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(c)

print('Fixed!')

