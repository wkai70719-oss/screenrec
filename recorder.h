#ifndef SCREENREC_RECORDER_H
#define SCREENREC_RECORDER_H
int rec_start(const char *path);
int rec_failed(void);
int rec_stop(void);
const char *rec_error(void);
#endif
int rec_has_frame(void);

