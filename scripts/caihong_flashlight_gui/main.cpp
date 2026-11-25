// SPDX-License-Identifier: GPL-2.0-only
// Native Qt6 touch-friendly Flashlight control UI for OnePlus Pad Pro (Caihong)

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QProcess>
#include <QPushButton>
#include <QRegularExpression>
#include <QSlider>
#include <QTimer>
#include <QVBoxLayout>
#include <QWidget>

namespace {

constexpr const char *kCliPath = "/usr/local/sbin/caihong-flashlight";

struct FlashState {
	bool on = false;
	int level = 40;
};

FlashState readFlashState()
{
	FlashState state;
	QProcess proc;
	proc.start(kCliPath, { "status" });
	if (!proc.waitForFinished(1500))
		return state;

	const QString out = QString::fromUtf8(proc.readAllStandardOutput());
	static const QRegularExpression modeRe(QStringLiteral("led_mode:\\s*(\\d+)"));
	static const QRegularExpression intensityRe(QStringLiteral("intensity_torch_mode:\\s*(\\d+)"));
	static const QRegularExpression brightRe(QStringLiteral("brightness=(\\d+)"));

	const auto modeMatch = modeRe.match(out);
	if (modeMatch.hasMatch()) {
		state.on = (modeMatch.captured(1).toInt() != 0);
		const auto intMatch = intensityRe.match(out);
		if (intMatch.hasMatch()) {
			const int raw = intMatch.captured(1).toInt();
			state.level = qBound(5, (raw * 100 + 250000) / 500000, 100);
		}
		return state;
	}

	const auto brightMatch = brightRe.match(out);
	if (brightMatch.hasMatch()) {
		const int b = brightMatch.captured(1).toInt();
		state.on = (b > 0);
		if (b > 0)
			state.level = qBound(5, (b * 100 + 127) / 255, 100);
	}
	return state;
}

bool setFlashlight(bool on, int level)
{
	QProcess proc;
	if (on)
		proc.start(kCliPath, { "on", QString::number(qBound(1, level, 100)) });
	else
		proc.start(kCliPath, { "off" });
	return proc.waitForFinished(2000) && proc.exitCode() == 0;
}

} // namespace

class FlashlightWindow : public QWidget {
public:
	explicit FlashlightWindow(QWidget *parent = nullptr)
		: QWidget(parent)
	{
		setWindowTitle(QStringLiteral("手电筒"));
		setWindowIcon(QIcon::fromTheme(QStringLiteral("flashlight-on")));
		setMinimumSize(400, 280);

		auto *root = new QVBoxLayout(this);
		root->setContentsMargins(24, 20, 24, 20);
		root->setSpacing(16);

		statusLabel_ = new QLabel(this);
		statusLabel_->setAlignment(Qt::AlignCenter);
		statusLabel_->setStyleSheet(QStringLiteral("font-size: 16px; font-weight: 600;"));
		root->addWidget(statusLabel_);

		toggleBtn_ = new QPushButton(this);
		toggleBtn_->setMinimumHeight(64);
		toggleBtn_->setCheckable(true);
		root->addWidget(toggleBtn_);

		auto *sliderRow = new QHBoxLayout();
		sliderRow->setSpacing(12);
		auto *brightCaption = new QLabel(QStringLiteral("亮度"), this);
		slider_ = new QSlider(Qt::Horizontal, this);
		slider_->setRange(5, 100);
		slider_->setValue(40);
		slider_->setMinimumHeight(36);
		levelLabel_ = new QLabel(QStringLiteral("40%"), this);
		levelLabel_->setMinimumWidth(46);
		levelLabel_->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
		sliderRow->addWidget(brightCaption);
		sliderRow->addWidget(slider_, 1);
		sliderRow->addWidget(levelLabel_);
		root->addLayout(sliderRow);

		auto *presetRow = new QHBoxLayout();
		presetRow->setSpacing(10);
		for (const int pct : { 20, 50, 100 }) {
			auto *btn = new QPushButton(QStringLiteral("%1%").arg(pct), this);
			btn->setMinimumHeight(40);
			connect(btn, &QPushButton::clicked, this, [this, pct]() {
				slider_->setValue(pct);
				applyLevel(pct, true);
			});
			presetRow->addWidget(btn);
		}
		root->addLayout(presetRow);

		connect(toggleBtn_, &QPushButton::clicked, this, [this](bool checked) {
			if (setFlashlight(checked, slider_->value())) {
				isOn_ = checked;
			}
			syncUi();
		});

		connect(slider_, &QSlider::valueChanged, this, [this](int val) {
			levelLabel_->setText(QStringLiteral("%1%").arg(val));
			if (isOn_ && !syncing_)
				applyLevel(val, false);
		});

		auto *pollTimer = new QTimer(this);
		pollTimer->setInterval(1500);
		connect(pollTimer, &QTimer::timeout, this, &FlashlightWindow::refreshFromHardware);
		pollTimer->start();

		refreshFromHardware();
	}

private:
	void applyLevel(int level, bool forceOn)
	{
		if (forceOn)
			isOn_ = true;
		if (isOn_)
			setFlashlight(true, level);
		syncUi();
	}

	void refreshFromHardware()
	{
		const FlashState st = readFlashState();
		syncing_ = true;
		isOn_ = st.on;
		if (st.on && !slider_->isSliderDown())
			slider_->setValue(st.level);
		syncUi();
		syncing_ = false;
	}

	void syncUi()
	{
		toggleBtn_->setChecked(isOn_);
		if (isOn_) {
			statusLabel_->setText(QStringLiteral("状态：已开启（%1%）").arg(slider_->value()));
			toggleBtn_->setText(QStringLiteral("关闭手电筒"));
			toggleBtn_->setIcon(QIcon::fromTheme(QStringLiteral("flashlight-on")));
			toggleBtn_->setStyleSheet(QStringLiteral(
				"QPushButton { font-size: 18px; font-weight: bold; border-radius: 10px;"
				" background-color: #d97706; color: #ffffff; padding: 10px; }"
				"QPushButton:hover { background-color: #b45309; }"));
		} else {
			statusLabel_->setText(QStringLiteral("状态：已关闭"));
			toggleBtn_->setText(QStringLiteral("开启手电筒"));
			toggleBtn_->setIcon(QIcon::fromTheme(QStringLiteral("flashlight-off")));
			toggleBtn_->setStyleSheet(QStringLiteral(
				"QPushButton { font-size: 18px; font-weight: bold; border-radius: 10px;"
				" padding: 10px; }"));
		}
	}

	QLabel *statusLabel_ = nullptr;
	QPushButton *toggleBtn_ = nullptr;
	QSlider *slider_ = nullptr;
	QLabel *levelLabel_ = nullptr;
	bool isOn_ = false;
	bool syncing_ = false;
};

int main(int argc, char **argv)
{
	QApplication app(argc, argv);
	app.setApplicationName(QStringLiteral("caihong-flashlight-gui"));
	app.setDesktopFileName(QStringLiteral("caihong-flashlight"));
	FlashlightWindow win;
	win.show();
	return app.exec();
}
